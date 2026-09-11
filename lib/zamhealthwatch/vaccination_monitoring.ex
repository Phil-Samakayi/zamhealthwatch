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
    * The brief also says this module "feeds risk scoring" - deliberately
      **not** wired into `PredictiveAnalytics` this slice.
      `PredictiveAnalytics.list_risk_scores/1` is scored per *facility*
      today, while this module reports per *district* - blending the two
      needs `PredictiveAnalytics` itself to move to district-level
      scoring first (real, separate work, though `Facility.district_id`
      being castable now finally unblocks it), not a quick bolt-on here.
      Logged as the natural next iteration once this slice is stable,
      not silently dropped.

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
