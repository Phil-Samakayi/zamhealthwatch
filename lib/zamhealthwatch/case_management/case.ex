defmodule ZamHealthWatch.CaseManagement.Case do
  use Ecto.Schema
  import Ecto.Changeset

  @disease_options [
    {"Cholera", :cholera},
    {"Malaria", :malaria},
    {"Typhoid", :typhoid},
    {"COVID-19", :covid19},
    {"Measles", :measles}
  ]

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

  @doc """
  Returns the `{label, value}` options list for every valid `disease`
  value, in display order - the single source of truth `disease_label/1`
  and every disease-picking `<select>` in this project (`CaseLive.Index`'s
  report form, `EpidemiologyLive.Index`'s by-disease stat tiles,
  `LabLive.Index`'s lab-test-to-case picker) now share, instead of each
  LiveView keeping its own copy. Extracted here - not into
  `CaseManagement` itself - because this is exactly the kind of thing
  Information Expert says belongs with the schema that declares the
  valid values in the first place, not the context around it. Pulled out
  once a third consumer needed the same list; two wasn't yet a pattern
  worth generalizing (see Iteration 2's GIS Mapping decision log, which
  first flagged this duplication and deliberately left it alone).

  ## Examples

      iex> disease_options()
      [{"Cholera", :cholera}, ...]

  """
  def disease_options, do: @disease_options

  @doc """
  Returns a human-readable label for a `disease` value (e.g. `:covid19`
  -> `"COVID-19"`), looked up in `disease_options/0` rather than derived
  with `Phoenix.Naming.humanize/1` - humanize's underscore-to-space,
  one-capital-letter rule can't produce "COVID-19" from `:covid19`.

  ## Examples

      iex> disease_label(:covid19)
      "COVID-19"

  """
  def disease_label(disease) do
    Enum.find_value(@disease_options, Phoenix.Naming.humanize(disease), fn {label, value} ->
      value == disease && label
    end)
  end
end
