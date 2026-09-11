defmodule ZamHealthWatch.HospitalCapacity do
  @moduledoc """
  The HospitalCapacity context - the brief's "bed occupancy, ICU
  availability, admission rates by facility - the 'can the system
  absorb this' view" module. The last of the brief's four Construction
  modules (Laboratory Reporting, Vaccination Monitoring, Drug
  Availability, Hospital Capacity).

  Scoped down for this first slice (full reasoning in docs/ITERATIONS.md):

    * Reported at *facility* level (`facility_id`), same grain as
      `Case`/`LabTest`/`DrugStock` - the brief's own phrasing is "by
      facility". Unlike `VaccinationMonitoring`'s district-mismatch with
      `PredictiveAnalytics`, this module's facility grain already
      matches `PredictiveAnalytics.list_risk_scores/1`'s current
      per-facility scoring - a real, comparatively easy future
      integration, deliberately not built this slice (see below).
    * A capacity report is submitted once, not advanced through a
      lifecycle - same "no request/confirm two-phase workflow, no
      editing yet" shape `VaccinationMonitoring` and `DrugAvailability`
      already settled on, for the same reason: a snapshot report either
      gets corrected by a new submission or it doesn't.
    * Not wired into `PredictiveAnalytics.list_risk_scores/1` this
      slice, even though the facility-level grain would make it a
      comparatively quick addition (unlike `VaccinationMonitoring`'s
      genuine district/facility mismatch) - still real, separate work
      (deciding how bed strain should combine with the existing
      case-trend tier, not something to guess at without a real use
      case), and this session's own scope for this slice was building
      the module itself. Logged here as the natural next integration,
      easier than Vaccination Monitoring's.

  Depends on `Geography` (a record's `facility_id`) and `Accounts` (its
  `reported_by_id`) the same decoupled way every other context in this
  project does - `foreign_key_constraint/2` on the schema, no
  cross-context associations.
  """

  import Ecto.Query, warn: false
  alias ZamHealthWatch.Repo

  alias ZamHealthWatch.HospitalCapacity.CapacityReport

  @doc """
  Subscribes to notifications about any capacity report changes.

  The broadcasted messages match the pattern:

    * {:created, %CapacityReport{}}

  Own `"capacity_reports"` topic, not reused from any other context's -
  same per-context topic precedent every module in this project has
  set.
  """
  def subscribe_capacity_reports do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "capacity_reports")
  end

  defp broadcast_capacity_report(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "capacity_reports", message)
  end

  @doc """
  Returns the list of capacity reports, most recently reported first.

  ## Examples

      iex> list_capacity_reports()
      [%CapacityReport{}, ...]

  """
  def list_capacity_reports do
    Repo.all(from c in CapacityReport, order_by: [desc: c.inserted_at])
  end

  @doc """
  Gets a single capacity report.

  Raises `Ecto.NoResultsError` if it does not exist.

  ## Examples

      iex> get_capacity_report!(123)
      %CapacityReport{}

  """
  def get_capacity_report!(id), do: Repo.get!(CapacityReport, id)

  @doc """
  Records a new capacity report submission.

  ## Examples

      iex> record_capacity(%{field: value})
      {:ok, %CapacityReport{}}

      iex> record_capacity(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def record_capacity(attrs) do
    with {:ok, report = %CapacityReport{}} <-
           %CapacityReport{}
           |> CapacityReport.changeset(attrs)
           |> Repo.insert() do
      broadcast_capacity_report({:created, report})
      {:ok, report}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking capacity report changes.

  ## Examples

      iex> change_capacity_report(report)
      %Ecto.Changeset{data: %CapacityReport{}}

  """
  def change_capacity_report(%CapacityReport{} = report, attrs \\ %{}) do
    CapacityReport.changeset(report, attrs)
  end
end
