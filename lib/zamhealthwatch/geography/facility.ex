defmodule ZamHealthWatch.Geography.Facility do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "facilities" do
    field :name, :string
    field :code, :string
    field :latitude, :float
    field :longitude, :float
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

  `latitude`/`longitude` are plain floats, not required - a facility
  can exist without known coordinates yet (there's still no
  facility-management UI; only seeds/fixtures create them). Validated
  as real-world coordinates when present, but not validated against
  Zambia's actual bounds specifically - not worth the complexity for
  what's still hand-entered demo seed data (see
  `MapLive.Index`/`Geography.list_facilities_with_coordinates/0` for
  where "has coordinates" actually matters).

  `district_id` was a column on this schema from Iteration 0 but wasn't
  castable here until now - Iteration 1's Epidemiology Dashboard
  explicitly deferred by-district aggregation for exactly that reason
  (see docs/ITERATIONS.md). Optional, like `latitude`/`longitude` and
  for the same reason - no facility-management UI yet, so a facility
  without a known district should still be creatable, it just won't
  contribute to any district-level breakdown. Checked with
  `foreign_key_constraint/2` rather than reaching into `District`
  directly, same decoupling as `facility_id`/`reported_by_id` on
  `CaseManagement.Case`.
  """
  def changeset(facility, attrs) do
    facility
    |> cast(attrs, [:name, :code, :latitude, :longitude, :district_id])
    |> validate_required([:name, :code])
    |> validate_format(:code, ~r/^[A-Z0-9]+$/, message: "must be uppercase letters/numbers only")
    |> unique_constraint(:code)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> foreign_key_constraint(:district_id)
  end
end
