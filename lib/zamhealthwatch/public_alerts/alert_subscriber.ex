defmodule ZamHealthWatch.PublicAlerts.AlertSubscriber do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A phone number opted in to receive public alert SMS broadcasts.

  Named `AlertSubscriber`, not `Subscriber` - `PublicAlerts.Subscriber`
  is already taken by the permanent `GenServer` that reacts to newly
  reported cases (a process, not a phone number); a second, different
  meaning for the same bare name in the same context would be exactly
  the kind of ambiguity this project's own naming has avoided
  everywhere else.

  Deliberately minimal: a phone number and when it subscribed, nothing
  else. No `active`/soft-delete flag - opting out (`PublicAlerts.unsubscribe/1`)
  deletes the row outright, same "no lifecycle without a real use case
  for one yet" call every other single-purpose schema in this project
  has made.
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "alert_subscribers" do
    field :phone, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  A changeset for subscribing a phone number. `unique_constraint/2`
  (not a pre-check `Repo.get_by/2`) is what actually prevents a
  duplicate row under concurrent SUBSCRIBE texts from the same number -
  `PublicAlerts.subscribe/1` treats that constraint violation as
  "already subscribed, nothing to do" rather than an error.

  Trims `phone` before anything else runs. Discovered during manual
  testing: `application/x-www-form-urlencoded` decodes a literal `+` as
  a space, so an inbound value sent without proper percent-encoding
  (`+260...` vs. the correct `%2B260...`) silently created a second,
  permanently distinct subscriber row (`" 260..."`) that `unique_constraint/2`
  could never catch and `unsubscribe/1`'s exact-match delete could never
  remove. Trimming doesn't fix every possible malformed inbound value -
  a real Africa's Talking webhook sends a clean MSISDN, so this is a
  defensive minimum, not full phone-number normalization (no E.164
  validation/formatting here either) - just enough to stop one specific,
  already-observed failure mode from quietly creating an un-unsubscribable
  duplicate.
  """
  def changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [:phone])
    |> update_change(:phone, &String.trim/1)
    |> validate_required([:phone])
    |> unique_constraint(:phone)
  end
end
