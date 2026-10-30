defmodule ZamHealthWatch.LabReporting do
  @moduledoc """
  The LabReporting context.

  Owns the lab test record - which case it's for, who requested it, and
  its result once one comes in (the brief's "Laboratory Reporting"
  module: "lab test requests and results, linked back to cases;
  confirms or downgrades surveillance signals"). A separate context
  from `CaseManagement`, not folded into it the way Disease
  Surveillance's aggregates were in Iteration 1 - a lab test is a
  genuinely distinct entity with its own two-state lifecycle
  (`:pending` -> `:resulted`, separate from a case's own
  classification), not just another query over the `cases` table. `CaseManagement` doesn't know this context
  exists; `LabReporting` depends on `CaseManagement`'s public API
  (`get_case!/1`, `update_case_status/2`) in one direction only, the
  same direction `PredictiveAnalytics` already depends on it and
  `Geography`.

  Two states, not three - no separate "sample collected" / "in
  progress" step. Nothing in this project talks to a real lab system
  yet (no LIS integration, no barcode/sample-tracking use case), so a
  test is either awaiting a result or has one; a finer-grained workflow
  would be designing ahead of a use case that doesn't exist yet, the
  same call this project has made repeatedly for every other
  not-yet-needed distinction.
  """

  import Ecto.Query, warn: false
  alias ZamHealthWatch.Repo

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.LabReporting.LabTest

  @doc """
  Subscribes to notifications about any lab test changes.

  The broadcasted messages match the pattern:

    * {:created, %LabTest{}}
    * {:updated, %LabTest{}}

  A separate `"lab_tests"` topic, not reused from `CaseManagement`'s
  `"cases"` one - the same "each context broadcasts on its own topic"
  precedent `Geography`'s `"districts"`/`"facilities"` topics already
  set. `record_result/3`'s own side effect on the linked case still
  goes out on `"cases"` too, via `CaseManagement.update_case_status/2`
  itself - nothing extra is needed here for that to reach the other
  LiveViews already subscribed to it.
  """
  def subscribe_lab_tests do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "lab_tests")
  end

  defp broadcast_lab_test(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "lab_tests", message)
  end

  @doc """
  Returns the list of lab tests, most recently requested first.

  ## Examples

      iex> list_lab_tests()
      [%LabTest{}, ...]

  """
  def list_lab_tests do
    Repo.all(from t in LabTest, order_by: [desc: t.inserted_at])
  end

  @doc """
  Returns the list of lab tests requested against cases at a given
  facility, most recently requested first.

  `LabTest` has no `facility_id` of its own - only `case_id`, linking
  to `CaseManagement.Case` (which does carry `facility_id`) - so
  scoping by facility means first asking `CaseManagement` which cases
  are at that facility, then filtering lab tests down to that set of
  ids. A plain SQL join would do it in one query, but would mean this
  context reaching directly into `CaseManagement.Case`'s schema - the
  same cross-context decoupling every other context in this project
  keeps (`foreign_key_constraint/2` only, no cross-context
  associations). Built for `LabLive.Index`'s Health Worker Portal
  facility-scoping (see docs/ITERATIONS.md) - a facility with no cases
  simply has no lab tests either, no separate check needed.

  ## Examples

      iex> list_lab_tests_by_facility(facility_id)
      [%LabTest{}, ...]

  """
  def list_lab_tests_by_facility(facility_id) do
    case_ids = facility_id |> CaseManagement.list_cases_by_facility() |> Enum.map(& &1.id)

    Repo.all(from t in LabTest, where: t.case_id in ^case_ids, order_by: [desc: t.inserted_at])
  end

  @doc """
  Gets a single lab test.

  Raises `Ecto.NoResultsError` if the LabTest does not exist.

  ## Examples

      iex> get_lab_test!(123)
      %LabTest{}

      iex> get_lab_test!(456)
      ** (Ecto.NoResultsError)

  """
  def get_lab_test!(id), do: Repo.get!(LabTest, id)

  @doc """
  Requests a new lab test against an existing case.

  ## Examples

      iex> request_test(%{case_id: case.id, requested_by_id: user.id})
      {:ok, %LabTest{}}

      iex> request_test(%{})
      {:error, %Ecto.Changeset{}}

  """
  def request_test(attrs) do
    with {:ok, lab_test = %LabTest{}} <-
           %LabTest{}
           |> LabTest.request_changeset(attrs)
           |> Repo.insert() do
      broadcast_lab_test({:created, lab_test})
      {:ok, lab_test}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking a new lab test request.

  ## Examples

      iex> change_lab_test(lab_test)
      %Ecto.Changeset{data: %LabTest{}}

  """
  def change_lab_test(%LabTest{} = lab_test, attrs \\ %{}) do
    LabTest.request_changeset(lab_test, attrs)
  end

  @result_recording_roles [:lab_officer]

  @doc """
  Returns `true` if a user holding `role` may enter lab results.

  Only `:lab_officer` (Iteration 15). In a real lab, results are entered
  by lab staff, and the clinicians and officers who use them don't
  enter or change them. Before this, any assigned role could record a
  result - including the district officer who'd act on it. Exposed so
  `LabLive.Index` can decide whether to show the result buttons by
  asking the same rule `record_result/3` enforces, rather than keeping
  its own copy.

  ## Examples

      iex> can_record_results?(:lab_officer)
      true

      iex> can_record_results?(:district_officer)
      false

  """
  def can_record_results?(role), do: role in @result_recording_roles

  @doc """
  Records a result for a pending lab test on behalf of `recorder` - any
  map with the recording user's `:id` and `:role`, such as
  `current_scope.user` - and applies its consequence to the linked case.

  Takes the id and role rather than an `%Accounts.User{}` pattern, the
  same decoupling from `Accounts`'s schema `CaseManagement.advance_case_status/2`
  keeps. Two checks happen here, not only in `LabLive.Index`'s
  rendering, so a forged event can't skip either one:

    * the recorder must be allowed to enter results - see
      `can_record_results?/1`.
    * the test must still be `:pending` - a `:resulted` test is a
      terminal state; re-recording would silently overwrite an existing
      result and could re-trigger its case side effect a second time.
      Fixing a wrong result is a correction, with its own history - not
      an overwrite.

  The recorder's id is stored as `resulted_by_id`, so every new result
  says who entered it.

  What a result does to the linked case (Information Expert: this
  context, not `CaseManagement`, knows what a lab result *means* for
  surveillance purposes, the same division of labour `PredictiveAnalytics`
  already draws for what a case-count trend means):

    * `:positive` confirms the signal - the case moves to `:confirmed`.
    * `:negative` rules it out - the case moves to `:not_a_case`. Until
      Iteration 15 this set `:resolved`, which also meant "recovered";
      a negative result means the patient never had the disease, so it
      now has its own classification (see `Case`'s `status` field).
    * `:inconclusive` changes nothing - "we don't know yet" isn't a
      real signal either way.

  Applied unconditionally via `CaseManagement.update_case_status/2`,
  regardless of the case's current status - the same "no stricter
  transition rule than the data layer already allows" call Iteration 1
  made for `Case.status_changeset/2` itself. A result landing on a
  case already classified some other way (e.g. a positive on a case an
  earlier test ruled out) reclassifies it rather than being silently
  ignored - there's no real second-order use case yet deciding
  what *should* happen in that narrower situation, so a more careful
  rule isn't guessed at here. Logged as a known, deliberate limitation,
  not silently attempted.

  ## Examples

      iex> record_result(lab_test, :positive, %{id: lab_officer_id, role: :lab_officer})
      {:ok, %LabTest{}}

      iex> record_result(lab_test, :positive, %{id: worker_id, role: :health_worker})
      {:error, :unauthorized}

      iex> record_result(%LabTest{status: :resulted}, :positive, lab_officer)
      {:error, :already_resulted}

  """
  def record_result(%LabTest{} = lab_test, result, %{id: recorder_id, role: role}) do
    cond do
      not can_record_results?(role) ->
        {:error, :unauthorized}

      lab_test.status == :resulted ->
        {:error, :already_resulted}

      true ->
        with {:ok, updated} <-
               lab_test
               |> LabTest.result_changeset(%{result: result, resulted_by_id: recorder_id})
               |> Repo.update() do
          broadcast_lab_test({:updated, updated})
          apply_result_to_case(updated)
          {:ok, updated}
        end
    end
  end

  defp apply_result_to_case(%LabTest{result: :positive, case_id: case_id}) do
    case_id
    |> CaseManagement.get_case!()
    |> CaseManagement.update_case_status(%{status: :confirmed})
  end

  defp apply_result_to_case(%LabTest{result: :negative, case_id: case_id}) do
    case_id
    |> CaseManagement.get_case!()
    |> CaseManagement.update_case_status(%{status: :not_a_case})
  end

  defp apply_result_to_case(%LabTest{result: :inconclusive}), do: :ok
end
