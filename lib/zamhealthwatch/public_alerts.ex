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
  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.SmsGateway

  alias ZamHealthWatch.PublicAlerts.AlertSubscriber

  @subscribe_keyword "SUBSCRIBE"
  @unsubscribe_keyword "STOP"

  @subscribe_reply "You're subscribed to ZamHealthWatch public health alerts. Reply STOP to unsubscribe at any time."
  @unsubscribe_reply "You've been unsubscribed from ZamHealthWatch public health alerts. Reply SUBSCRIBE to opt back in."

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

  ## Examples

      iex> subscribe("+260971234567")
      {:ok, %AlertSubscriber{}}

  """
  def subscribe(phone) when is_binary(phone) do
    case %AlertSubscriber{} |> AlertSubscriber.changeset(%{phone: phone}) |> Repo.insert() do
      {:ok, subscriber} ->
        {:ok, subscriber}

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :phone) do
          {:ok, Repo.get_by!(AlertSubscriber, phone: phone)}
        else
          {:error, changeset}
        end
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
    Repo.delete_all(from s in AlertSubscriber, where: s.phone == ^phone)
    :ok
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
        {:ok, _subscriber} = subscribe(from)
        SmsGateway.send_sms(from, @subscribe_reply)
        :handled

      @unsubscribe_keyword ->
        :ok = unsubscribe(from)
        SmsGateway.send_sms(from, @unsubscribe_reply)
        :handled

      _ ->
        :not_a_keyword
    end
  end
end
