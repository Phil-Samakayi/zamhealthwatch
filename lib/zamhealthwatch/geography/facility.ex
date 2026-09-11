defmodule ZamHealthWatch.Geography.Facility do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "facilities" do
    field :name, :string
    field :code, :string
    field :district_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  `code` is a short, unique, uppercase identifier (e.g. "UTH") - added
  for `SmsReporting` to address a facility from inside a plain-text SMS,
  where a `name` (spaces, arbitrary length) or a `binary_id` (nobody is
  typing a UUID on a feature phone) don't work. Required on every
  facility going forward, not just SMS-reported ones, so there's one
  consistent identity scheme rather than "has a code" being a special
  case. See docs/ITERATIONS.md, Iteration 2, for why this needed
  `mix ecto.reset` rather than a backfill migration.
  """
  def changeset(facility, attrs) do
    facility
    |> cast(attrs, [:name, :code])
    |> validate_required([:name, :code])
    |> validate_format(:code, ~r/^[A-Z0-9]+$/, message: "must be uppercase letters/numbers only")
    |> unique_constraint(:code)
  end
end
