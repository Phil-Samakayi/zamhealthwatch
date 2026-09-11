defmodule ZamHealthWatch.HospitalCapacity.CapacityReport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "capacity_reports" do
    field :total_beds, :integer
    field :occupied_beds, :integer
    field :icu_beds_total, :integer
    field :icu_beds_occupied, :integer
    field :admissions_today, :integer
    field :facility_id, :binary_id
    field :reported_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A capacity report changeset - one submission covering a given
  facility's bed occupancy, ICU status, and recent admissions (the
  brief's own "bed occupancy, ICU availability, admission rates by
  facility" framing). Same "reported once, no lifecycle, no editing
  yet" shape `VaccinationMonitoring.VaccinationRecord` and
  `DrugAvailability.DrugStock` already settled into.

  `occupied_beds` and `icu_beds_occupied` are **not** validated against
  `total_beds`/`icu_beds_total` - a facility genuinely running over its
  nominal capacity (overflow beds, hallway admissions) during an active
  outbreak is exactly the "can the system absorb this" signal this
  module exists to surface, not invalid data to reject. Same reasoning
  `VaccinationRecord.coverage_rate/1` already applied to doses exceeding
  a target population.

  `facility_id` and `reported_by_id` are checked against
  `Geography.Facility` and `Accounts.User` via `foreign_key_constraint/2`
  rather than by reaching into those schemas directly, same decoupling
  as every other context in this project.
  """
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :total_beds,
      :occupied_beds,
      :icu_beds_total,
      :icu_beds_occupied,
      :admissions_today,
      :facility_id,
      :reported_by_id
    ])
    |> validate_required([
      :total_beds,
      :occupied_beds,
      :icu_beds_total,
      :icu_beds_occupied,
      :admissions_today,
      :facility_id,
      :reported_by_id
    ])
    |> validate_number(:total_beds, greater_than: 0)
    |> validate_number(:occupied_beds, greater_than_or_equal_to: 0)
    |> validate_number(:icu_beds_total, greater_than_or_equal_to: 0)
    |> validate_number(:icu_beds_occupied, greater_than_or_equal_to: 0)
    |> validate_number(:admissions_today, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:facility_id)
    |> foreign_key_constraint(:reported_by_id)
  end

  @doc """
  Returns the general bed occupancy rate as a float, e.g. `0.8` for
  80%. `total_beds` is always > 0 (changeset-enforced), so this never
  divides by zero. Not capped at `1.0`, for the same reason nothing on
  this schema is - see `changeset/2`.

  ## Examples

      iex> bed_occupancy_rate(%CapacityReport{occupied_beds: 80, total_beds: 100})
      0.8

  """
  def bed_occupancy_rate(%__MODULE__{occupied_beds: occupied, total_beds: total}) do
    occupied / total
  end

  @doc """
  Returns the ICU occupancy rate as a float, or `nil` if the facility
  has no ICU beds at all (`icu_beds_total == 0`) - a real, valid state
  for a smaller facility, not something to force a `0.0`/undefined rate
  onto. Callers (the LiveView) render this as a dash rather than a
  percentage in that case.

  ## Examples

      iex> icu_occupancy_rate(%CapacityReport{icu_beds_occupied: 3, icu_beds_total: 4})
      0.75

      iex> icu_occupancy_rate(%CapacityReport{icu_beds_occupied: 0, icu_beds_total: 0})
      nil

  """
  def icu_occupancy_rate(%__MODULE__{icu_beds_total: 0}), do: nil

  def icu_occupancy_rate(%__MODULE__{icu_beds_occupied: occupied, icu_beds_total: total}) do
    occupied / total
  end

  @doc """
  Returns the number of free ICU beds (`icu_beds_total - icu_beds_occupied`)
  - the brief's own "ICU availability" framing, computed rather than
  reported directly so it can never drift out of sync with the two
  numbers it's derived from. Can go negative under the same
  over-capacity reasoning `changeset/2` documents - not clamped to zero.

  ## Examples

      iex> icu_beds_available(%CapacityReport{icu_beds_total: 4, icu_beds_occupied: 3})
      1

  """
  def icu_beds_available(%__MODULE__{icu_beds_total: total, icu_beds_occupied: occupied}) do
    total - occupied
  end

  @doc """
  Returns `:adequate`, `:near_capacity`, or `:over_capacity` from the
  general bed occupancy rate - `< 80%` / `80-99%` / `>= 100%`. Same
  honestly-flagged-arbitrary threshold spirit as
  `PredictiveAnalytics.RiskScore`'s tier cutoffs and
  `VaccinationRecord`'s coverage badge thresholds, not calibrated
  against a real Zambia hospital-capacity target yet. Driven by general
  bed occupancy only, not ICU occupancy - stacking two independent tier
  systems into one first slice would be guessing at a combined-severity
  rule with no real use case behind it yet.

  ## Examples

      iex> capacity_status(%CapacityReport{occupied_beds: 50, total_beds: 100})
      :adequate

  """
  def capacity_status(%__MODULE__{} = report) do
    rate = bed_occupancy_rate(report)

    cond do
      rate >= 1.0 -> :over_capacity
      rate >= 0.8 -> :near_capacity
      true -> :adequate
    end
  end
end
