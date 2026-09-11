defmodule ZamHealthWatch.VaccinationMonitoring.VaccinationRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @antigen_options [
    {"BCG", :bcg},
    {"OPV (Polio)", :opv},
    {"Pentavalent", :penta},
    {"Measles-Rubella", :measles_rubella},
    {"PCV (Pneumococcal)", :pcv}
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "vaccination_records" do
    field :antigen, Ecto.Enum, values: [:bcg, :opv, :penta, :measles_rubella, :pcv]
    field :campaign, :string
    field :doses_administered, :integer
    field :target_population, :integer
    field :district_id, :binary_id
    field :reported_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A vaccination coverage record changeset - one submission covering a
  given district/antigen/campaign combination (the brief's own grouping
  for this module). Unlike `Case` or `LabTest`, there's no lifecycle to
  split into a separate changeset - a coverage figure is reported once,
  not advanced through states, so this is the only changeset this
  schema needs (no editing yet - see VaccinationMonitoring's moduledoc).

  `district_id` and `reported_by_id` are checked against
  `Geography.District` and `Accounts.User` via `foreign_key_constraint/2`
  rather than by reaching into those schemas directly, same decoupling
  as `Case.changeset/2` and `LabTest.request_changeset/2`.
  """
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :antigen,
      :campaign,
      :doses_administered,
      :target_population,
      :district_id,
      :reported_by_id
    ])
    |> validate_required([
      :antigen,
      :campaign,
      :doses_administered,
      :target_population,
      :district_id,
      :reported_by_id
    ])
    |> validate_number(:doses_administered, greater_than_or_equal_to: 0)
    |> validate_number(:target_population, greater_than: 0)
    |> foreign_key_constraint(:district_id)
    |> foreign_key_constraint(:reported_by_id)
  end

  @doc """
  Returns the `{label, value}` options list for every valid `antigen`
  value, in display order - same "single source of truth on the schema"
  pattern `Case.disease_options/0` established. Applied from the start
  here (not waiting for a second consumer) since `VaccinationLive.Index`'s
  own form and table already both need it.

  ## Examples

      iex> antigen_options()
      [{"BCG", :bcg}, ...]

  """
  def antigen_options, do: @antigen_options

  @doc """
  Returns a human-readable label for an `antigen` value (e.g. `:opv` ->
  `"OPV (Polio)"`), looked up in `antigen_options/0` rather than derived
  with `Phoenix.Naming.humanize/1` - same reasoning as `Case.disease_label/1`.

  ## Examples

      iex> antigen_label(:opv)
      "OPV (Polio)"

  """
  def antigen_label(antigen) do
    Enum.find_value(@antigen_options, Phoenix.Naming.humanize(antigen), fn {label, value} ->
      value == antigen && label
    end)
  end

  @doc """
  Returns the coverage rate for a record as a float, e.g. `0.8` for 80%.

  Deliberately **not** capped at `1.0` - `doses_administered` exceeding
  `target_population` is a real, meaningful signal (a campaign reaching
  more people than its original target estimate), not invalid data to
  clamp away.

  Information Expert: the schema holding `doses_administered` and
  `target_population` is what answers "what's the coverage", not the
  context or the LiveView.

  ## Examples

      iex> coverage_rate(%VaccinationRecord{doses_administered: 80, target_population: 100})
      0.8

  """
  def coverage_rate(%__MODULE__{doses_administered: doses, target_population: target}) do
    doses / target
  end
end
