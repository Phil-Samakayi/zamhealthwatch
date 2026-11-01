defmodule ZamHealthWatch.PublicAlerts do
  @moduledoc """
  The Public Alerts context.

  Before this iteration, "Public Alerts" was only `AlertWorker` (mock,
  `Logger`-only delivery) and `Subscriber` (the `GenServer` that reacts
  to a newly reported case) - real modules doing real work, but nothing
  in this project actually answered "who receives an alert", and
  nothing tied an inbound "I want alerts" SMS to anything durable. This
  context is that missing piece: who's subscribed
  (`AlertSubscriber`/`subscribe/1`/`unsubscribe/1`/`list_subscriber_phones/0`),
  and the inbound side of that - recognizing a `SUBSCRIBE`/`STOP` SMS
  keyword and acting on it (`handle_inbound_sms/2`).

  `handle_inbound_sms/2` is called from `SmsWebhookController` itself,
  not routed through `SmsReporting.Pipeline`'s Broadway wiring the way
  case reports are - a single-row subscribe/unsubscribe write is a
  fundamentally smaller, synchronous operation than parsing and
  creating a `CaseManagement.Case`, and doesn't need Broadway's
  demand-driven backpressure to justify the extra moving parts. The
  controller is the right place to decide "is this a subscription
  keyword or a case report" (GRASP *Controller* - routing one inbound
  webhook request to the right handler is exactly its job), not
  `SmsReporting`, which has no reason to know `PublicAlerts` exists.

  Depends on `SmsGateway` to send the SUBSCRIBE/STOP confirmation reply
  and (from `AlertWorker`) the alert broadcast itself - same one-way
  dependency direction as everywhere else in this project.
  """

  import Ecto.Query, warn: false
  require Logger

  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.SmsGateway

  alias ZamHealthWatch.PublicAlerts.AlertSubscriber

  @subscribe_keyword "SUBSCRIBE"
  @unsubscribe_keyword "STOP"

  @subscribe_reply "You're subscribed to ZamHealthWatch public health alerts. Reply STOP to unsubscribe at any time."
  @unsubscribe_reply "You've been unsubscribed from ZamHealthWatch public health alerts. Reply SUBSCRIBE to opt back in."
  @already_subscribed_reply "You're already subscribed to ZamHealthWatch public health alerts. Reply STOP to unsubscribe."
  @not_subscribed_reply "You aren't subscribed to ZamHealthWatch public health alerts. Reply SUBSCRIBE to opt in."

  @doc """
  Returns the list of every subscribed phone number.

  Built for `AlertWorker`'s broadcast - just the phone numbers, not
  full `AlertSubscriber` structs, since that's all a caller sending SMS
  needs.

  ## Examples

      iex> list_subscriber_phones()
      ["+260971234567"]

  """
  def list_subscriber_phones do
    Repo.all(from s in AlertSubscriber, select: s.phone)
  end

  @doc """
  Subscribes a phone number to public alerts.

  Idempotent - subscribing an already-subscribed number succeeds
  without creating a duplicate row (`AlertSubscriber.changeset/2`'s
  `unique_constraint/2` is what actually enforces this; a second
  SUBSCRIBE from the same number racing the first is exactly the case
  a pre-check `Repo.get_by/2` wouldn't safely cover).

  The duplicate-recovery lookup below reads the phone number back out
  of the changeset (`Ecto.Changeset.get_field/2`), not the raw `phone`
  argument - `AlertSubscriber.changeset/2` trims it, so a caller
  passing e.g. `" +260971234567"` inserts (and conflicts on)
  `"+260971234567"`; looking the row back up by the untrimmed argument
  would raise `Ecto.NoResultsError` instead of returning it. This was a
  real bug, not a hypothetical - it surfaced the moment the trim was
  added to the changeset, caught by a test exercising this exact
  "whitespace-padded duplicate" path.

  ## Examples

      iex> subscribe("+260971234567")
      {:ok, %AlertSubscriber{}}

  """
  def subscribe(phone) when is_binary(phone) do
    case insert_subscriber(phone) do
      {:error, changeset} -> {:error, changeset}
      {_new_or_existing, subscriber} -> {:ok, subscriber}
    end
  end

  @doc """
  Subscribes a phone number, saying whether it was already subscribed
  (Iteration 23): `:subscribed` or `:already_subscribed`. Same idempotent
  write as `subscribe/1`; the SMS and USSD replies use the answer to
  tell someone who's already on the list that they are, instead of
  confirming a subscription that didn't change anything.
  """
  def opt_in(phone) when is_binary(phone) do
    case insert_subscriber(phone) do
      {:error, changeset} -> {:error, changeset}
      {status, _subscriber} -> status
    end
  end

  # The answer comes from the insert itself - a new row, or the unique
  # constraint saying the number is already there - not from a lookup
  # beforehand, which two simultaneous SUBSCRIBEs could both pass. Only
  # the unique constraint means "already subscribed"; any other phone
  # error (a blank number, say) is a real error.
  defp insert_subscriber(phone) do
    changeset = %AlertSubscriber{} |> AlertSubscriber.changeset(%{phone: phone})

    case Repo.insert(changeset) do
      {:ok, subscriber} ->
        {:subscribed, subscriber}

      {:error, changeset} ->
        if already_subscribed?(changeset) do
          trimmed = Ecto.Changeset.get_field(changeset, :phone)
          {:already_subscribed, Repo.get_by!(AlertSubscriber, phone: trimmed)}
        else
          {:error, changeset}
        end
    end
  end

  defp already_subscribed?(changeset) do
    case Keyword.get(changeset.errors, :phone) do
      {_message, opts} -> opts[:constraint] == :unique
      nil -> false
    end
  end

  @doc """
  Unsubscribes a phone number from public alerts.

  A no-op (not an error) when the number was never subscribed - same
  "absence isn't an error to reject" call `HospitalCapacity.latest_capacity_by_facility/0`
  and others already make.

  ## Examples

      iex> unsubscribe("+260971234567")
      :ok

  """
  def unsubscribe(phone) when is_binary(phone) do
    _status = opt_out(phone)
    :ok
  end

  @doc """
  Unsubscribes a phone number, saying whether it was subscribed
  (Iteration 23): `:unsubscribed` or `:not_subscribed`. The number is
  trimmed first, the same way `subscribe/1` trims it before storing it,
  so a padded STOP still finds the subscription.
  """
  def opt_out(phone) when is_binary(phone) do
    trimmed = String.trim(phone)

    case Repo.delete_all(from s in AlertSubscriber, where: s.phone == ^trimmed) do
      {0, _} -> :not_subscribed
      {_deleted, _} -> :unsubscribed
    end
  end

  @doc """
  Handles one inbound SMS as a possible subscription keyword.

  Recognizes exactly two, case-insensitively and after trimming
  whitespace: `SUBSCRIBE` and `STOP` - the same "smallest possible
  grammar" call `SmsReporting.report_from_sms/2` already made for its
  own `REPORT <DISEASE> <FACILITY_CODE>` grammar, for the same reason
  (no free-text/NLP risk worth taking on for a first cut). Sends a
  confirmation reply via `SmsGateway` either way, then returns
  `:handled`. Anything else returns `:not_a_keyword`, letting the
  caller (`SmsWebhookController`) fall through to
  `SmsReporting.Pipeline.push/2` instead.

  ## Examples

      iex> handle_inbound_sms("+260971234567", "SUBSCRIBE")
      :handled

      iex> handle_inbound_sms("+260971234567", "REPORT CHOLERA UTH")
      :not_a_keyword

  """
  def handle_inbound_sms(from, text) when is_binary(from) and is_binary(text) do
    case text |> String.trim() |> String.upcase() do
      @subscribe_keyword ->
        reply =
          case opt_in(from) do
            :subscribed -> @subscribe_reply
            :already_subscribed -> @already_subscribed_reply
          end

        SmsGateway.send_sms(from, reply)
        :handled

      @unsubscribe_keyword ->
        reply =
          case opt_out(from) do
            :unsubscribed -> @unsubscribe_reply
            :not_subscribed -> @not_subscribed_reply
          end

        SmsGateway.send_sms(from, reply)
        :handled

      _ ->
        :not_a_keyword
    end
  end

  @doc """
  Sends `message` to each of `phones` through `SmsGateway`, logging any
  individual failure.

  Returns `:ok`, or `{:error, :all_deliveries_failed}` when there was at
  least one number and every send failed - the shape a systemic outage
  (the SMS provider itself down) takes, and the only case worth Oban
  retrying the whole job for (see `AlertWorker`'s moduledoc for why a
  handful of individual failures isn't). Shared by `AlertWorker` and
  `ReclassificationAlertWorker` since Iteration 15, so the two can't
  drift apart on what counts as a failed delivery.
  """
  def deliver_to(phones, message) when is_list(phones) and is_binary(message) do
    results = Enum.map(phones, fn phone -> {phone, SmsGateway.send_sms(phone, message)} end)

    for {phone, {:error, reason}} <- results do
      Logger.error("Public alert SMS to #{phone} failed: #{inspect(reason)}")
    end

    if results != [] and Enum.all?(results, fn {_phone, result} -> result != :ok end) do
      {:error, :all_deliveries_failed}
    else
      :ok
    end
  end
end
