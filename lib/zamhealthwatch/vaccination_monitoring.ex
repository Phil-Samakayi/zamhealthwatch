defmodule ZamHealthWatch.VaccinationMonitoring do
  @moduledoc """
  The VaccinationMonitoring context - the brief's "coverage rates by
  district/antigen/campaign" module.

  Scoped down for this first slice (full reasoning in docs/ITERATIONS.md):

    * Coverage is reported directly at *district* level, not aggregated
      up from per-facility submissions - the brief's own phrasing groups
      by "district/antigen/campaign", and Zambia's real EPI reporting
      already compiles to district level before it reaches anyone this
      system would show it to. A facility-level submission workflow is
      a real possible future slice, not a gap this one is pretending
      doesn't exist.
    * A coverage figure is reported once, not advanced through a
      lifecycle - there's no "request, then confirm" two-phase workflow
      the way `LabReporting` has one, because there's no second phase to
      a coverage number: it either gets corrected by a new submission or
      it doesn't. No editing/deletion yet, same "no rule guessed at
      without a real use case" reasoning applied everywhere else in this
      project.
    * The brief also says this module "feeds risk scoring". It does as
      of Iteration 17: `PredictiveAnalytics.list_district_risks/1` reads
      each district's latest coverage through
      `latest_coverage_by_district/1`. Deferred until then because risk
      was scored per facility and coverage is per district.

  Depends on `Geography` (a record's `district_id`) and `Accounts` (its
  `reported_by_id`) the same decoupled way `CaseManagement` and
  `LabReporting` do - `foreign_key_constraint/2` on the schema, no
  cross-context associations.
  """

  import Ecto.Query, warn: false
  alias ZamHealthWatch.Repo

  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @doc """
  Subscribes to notifications about any vaccination record changes.

  The broadcasted messages match the pattern:

    * {:created, %VaccinationRecord{}}

  Own `"vaccination_records"` topic, not reused from `"cases"` or
  `"districts"` - same per-context topic precedent `LabReporting`
  ("lab_tests") and `Geography` ("districts"/"facilities") already set.
  """
  def subscribe_vaccination_records do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "vaccination_records")
  end

  defp broadcast_vaccination_record(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "vaccination_records", message)
  end

  @doc """
  Returns the list of vaccination records, most recently reported first.

  ## Examples

      iex> list_vaccination_records()
      [%VaccinationRecord{}, ...]

  """
  def list_vaccination_records do
    Repo.all(from v in VaccinationRecord, order_by: [desc: v.inserted_at])
  end

  @doc """
  Returns the list of vaccination records for a given district, most
  recently reported first.

  Added for the Health Worker Portal's facility-scoped screens (see
  docs/ITERATIONS.md) - a health worker only has a `facility_id`, not
  a `district_id` directly, so the scoping done by the caller
  (`VaccinationLive.Index`) is by the *district a worker's own
  facility sits in* (`Geography.get_facility!(facility_id).district_id`),
  not by facility itself. `VaccinationRecord` is genuinely
  district-grain - no `facility_id` column exists on it at all (see
  the moduledoc) - so this is the narrowest scoping this schema
  actually supports; a worker ends up seeing every record for their
  whole district, not only ones tied to their own facility
  specifically. Logged as a known, deliberate broadening, not a bug.

  ## Examples

      iex> list_vaccination_records_by_district(district_id)
      [%VaccinationRecord{}, ...]

  """
  def list_vaccination_records_by_district(district_id) do
    Repo.all(
      from v in VaccinationRecord,
        where: v.district_id == ^district_id,
        order_by: [desc: v.inserted_at]
    )
  end

  @doc """
  Returns the most recently reported record for `antigen` in each
  district that has one, as `%{district_id => VaccinationRecord}`.

  Built for `PredictiveAnalytics.list_district_risks/1` (Iteration 17).
  "Latest" is by report time, whatever the campaign: a newer submission
  is this system's current figure for that district, the same way
  `HospitalCapacity.latest_capacity_by_facility/0` treats capacity. A
  district with no record for the antigen is simply absent - the caller
  decides what "no data" means.

  ## Examples

      iex> latest_coverage_by_district(:measles_rubella)
      %{"district-uuid" => %VaccinationRecord{}}

  """
  def latest_coverage_by_district(antigen) do
    Repo.all(
      from v in VaccinationRecord,
        where: v.antigen == ^antigen,
        distinct: v.district_id,
        order_by: [asc: v.district_id, desc: v.inserted_at]
    )
    |> Map.new(&{&1.district_id, &1})
  end

  @doc """
  Gets a single vaccination record.

  Raises `Ecto.NoResultsError` if it does not exist.

  ## Examples

      iex> get_vaccination_record!(123)
      %VaccinationRecord{}

  """
  def get_vaccination_record!(id), do: Repo.get!(VaccinationRecord, id)

  @doc """
  Records a new vaccination coverage submission.

  ## Examples

      iex> record_vaccination(%{field: value})
      {:ok, %VaccinationRecord{}}

      iex> record_vaccination(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def record_vaccination(attrs) do
    with {:ok, record = %VaccinationRecord{}} <-
           %VaccinationRecord{}
           |> VaccinationRecord.changeset(attrs)
           |> Repo.insert() do
      broadcast_vaccination_record({:created, record})
      {:ok, record}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking vaccination record changes.

  ## Examples

      iex> change_vaccination_record(record)
      %Ecto.Changeset{data: %VaccinationRecord{}}

  """
  def change_vaccination_record(%VaccinationRecord{} = record, attrs \\ %{}) do
    VaccinationRecord.changeset(record, attrs)
  end
end
