defmodule ZamHealthWatch.CaseManagement.Case do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cases" do
    field :disease, Ecto.Enum, values: [:cholera, :malaria, :typhoid, :covid19, :measles]
    field :status, Ecto.Enum, values: [:suspected, :confirmed, :resolved], default: :suspected
    field :facility_id, :binary_id
    field :reported_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A case changeset for reporting a new case (or editing its core details).

  `status` is deliberately not castable here - a new case always starts
  `:suspected` (the schema default). Moving it through its lifecycle is
  `status_changeset/2`'s job, not this one's, so a single "edit case"
  form can't accidentally skip straight to `:resolved`.

  `facility_id` and `reported_by_id` are checked against `Geography.Facility`
  and `Accounts.User` via `foreign_key_constraint/2` rather than by reaching
  into those schemas directly, keeping contexts decoupled.
  """
  def changeset(case, attrs) do
    case
    |> cast(attrs, [:disease, :facility_id, :reported_by_id])
    |> validate_required([:disease, :facility_id, :reported_by_id])
    |> foreign_key_constraint(:facility_id)
    |> foreign_key_constraint(:reported_by_id)
  end

  @doc """
  A case changeset for moving it through its lifecycle
  (`:suspected` -> `:confirmed` -> `:resolved`).

  Only checks that `status` is one of the three valid values, not that
  the transition itself is legal (e.g. going straight back from `:resolved`
  to `:suspected` is allowed at the data layer for now) - there's no UI yet
  to make a stricter rule meaningful, so it isn't guessed at here. Revisit
  once a real case-management screen needs specific transition buttons.
  """
  def status_changeset(case, attrs) do
    case
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end
