defmodule ZamHealthWatch.LabReporting do
  @moduledoc """
  The LabReporting context.

  Owns the lab test record - which case it's for, who requested it, and
  its result once one comes in (the brief's "Laboratory Reporting"
  module: "lab test requests and results, linked back to cases;
  confirms or downgrades surveillance signals"). A separate context
  from `CaseManagement`, not folded into it the way Disease
  Surveillance's aggregates were in Iteration 1 - a lab test is a
  genuinely distinct entity with its own lifecycle (`:pending` ->
  `:resulted`, and since Iteration 15 `:corrected` or
  `:entered_in_error`), separate from a case's own classification, not
  just another query over the `cases` table. `CaseManagement` doesn't
  know this context exists; `LabReporting` depends on `CaseManagement`'s
  public API (`get_case!/1`, `apply_lab_verdict/2`) in one direction only, the
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
  alias ZamHealthWatch.LabReporting.LabResultCorrection
  alias ZamHealthWatch.LabReporting.LabTest

  @doc """
  Subscribes to notifications about any lab test changes.

  The broadcasted messages match the pattern:

    * {:created, %LabTest{}}
    * {:updated, %LabTest{}}

  A separate `"lab_tests"` topic, not reused from `CaseManagement`'s
  `"cases"` one - the same "each context broadcasts on its own topic"
  precedent `Geography`'s `"districts"`/`"facilities"` topics already
  set. A result's effect on the linked case still goes out on
  `"cases"` too, via `CaseManagement.apply_lab_verdict/2`
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

  What a result does to the linked case is decided here, not in
  `CaseManagement` (Information Expert: this context knows what a lab
  result *means* for surveillance). Since Iteration 15 the case's
  classification is recalculated from *all* of its current results
  rather than pushed by this one result alone - see `lab_verdict/1` and
  `CaseManagement.classification_for/2`. For a case's first result the
  effect is the familiar one: positive confirms, negative rules it out,
  inconclusive leaves a suspected case suspected. Recalculating instead
  of pushing is what lets a later correction or withdrawal flow through
  correctly.

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

      lab_test.status != :pending ->
        {:error, :already_resulted}

      true ->
        lab_test
        |> LabTest.result_changeset(%{result: result, resulted_by_id: recorder_id})
        |> Repo.update()
        |> after_result_change()
    end
  end

  @correction_roles [:lab_officer, :moh_admin]

  @doc """
  Returns `true` if a user holding `role` may correct or withdraw an
  issued lab result.

  Lab officers (the people who issue results) and MOH admins (oversight,
  for when the lab itself can't). Narrower than "anyone with a role" on
  purpose: a correction changes a case's classification for everyone,
  so it needs the same authority as issuing the result in the first
  place.
  """
  def can_correct_results?(role), do: role in @correction_roles

  @doc """
  Replaces an issued result with a corrected one, on behalf of
  `corrector` (any map with `:id` and `:role`), with a required
  `reason`.

  The previous result isn't lost: a `LabResultCorrection` row records
  what it was, what it became, why, who, and when, in the same
  transaction as the change itself. Corrections can be corrected again;
  each one adds to the history. The linked case's classification is
  recalculated afterwards.

  Refused when the corrector can't correct results (`:unauthorized`),
  the test has no issued result to correct - pending, or already
  withdrawn (`:not_correctable`) - or the "correction" is the result it
  already has (`:unchanged`). A missing or too-short reason comes back
  as `{:error, %Ecto.Changeset{}}`.
  """
  def correct_result(%LabTest{} = lab_test, new_result, reason, %{id: corrector_id, role: role}) do
    cond do
      not can_correct_results?(role) ->
        {:error, :unauthorized}

      lab_test.status not in [:resulted, :corrected] ->
        {:error, :not_correctable}

      new_result == lab_test.result ->
        {:error, :unchanged}

      true ->
        Repo.transact(fn ->
          with {:ok, _correction} <-
                 insert_correction(lab_test, :corrected, new_result, reason, corrector_id) do
            lab_test
            |> LabTest.correction_changeset(%{result: new_result})
            |> Repo.update()
          end
        end)
        |> after_result_change()
    end
  end

  @doc """
  Withdraws an issued result as entered in error, on behalf of
  `corrector`, with a required `reason` - for a result that should
  never have been recorded against this test at all (entered on the
  wrong case, say), as opposed to one that was simply wrong.

  The result stays visible but marked withdrawn, stops counting towards
  the case's classification, and can't be corrected afterwards - if
  the test was really done, request it again. Same refusals as
  `correct_result/4`, minus `:unchanged`.
  """
  def withdraw_result(%LabTest{} = lab_test, reason, %{id: corrector_id, role: role}) do
    cond do
      not can_correct_results?(role) ->
        {:error, :unauthorized}

      lab_test.status not in [:resulted, :corrected] ->
        {:error, :not_correctable}

      true ->
        Repo.transact(fn ->
          with {:ok, _correction} <-
                 insert_correction(lab_test, :entered_in_error, nil, reason, corrector_id) do
            lab_test
            |> LabTest.withdrawal_changeset()
            |> Repo.update()
          end
        end)
        |> after_result_change()
    end
  end

  @doc """
  Returns every correction and withdrawal, newest first - the history
  `LabLive.Index` shows under its table.
  """
  def list_corrections do
    Repo.all(from c in LabResultCorrection, order_by: [desc: c.inserted_at])
  end

  @doc """
  Returns a lab test's own correction history, oldest first - the order
  it happened in. The first entry's `previous_result` is the result as
  originally issued.
  """
  def list_corrections_for_lab_test(lab_test_id) do
    Repo.all(
      from c in LabResultCorrection,
        where: c.lab_test_id == ^lab_test_id,
        order_by: [asc: c.inserted_at]
    )
  end

  defp insert_correction(%LabTest{} = lab_test, kind, new_result, reason, corrector_id) do
    %LabResultCorrection{}
    |> LabResultCorrection.changeset(%{
      kind: kind,
      previous_result: lab_test.result,
      new_result: new_result,
      reason: reason,
      lab_test_id: lab_test.id,
      corrected_by_id: corrector_id
    })
    |> Repo.insert()
  end

  # Shared tail of every operation that changes what a test's result
  # is: broadcast the updated test, then recalculate the linked case's
  # classification from all of its current results.
  defp after_result_change({:ok, %LabTest{} = updated}) do
    broadcast_lab_test({:updated, updated})

    {:ok, _case} =
      updated.case_id
      |> CaseManagement.get_case!()
      |> CaseManagement.apply_lab_verdict(lab_verdict(updated.case_id))

    {:ok, updated}
  end

  defp after_result_change(error), do: error

  # What a case's *current* results say, as the verdict
  # CaseManagement.classification_for/2 takes: any positive wins, then
  # any negative, otherwise nothing conclusive. Pending tests have no
  # result yet, and withdrawn ones no longer count.
  defp lab_verdict(case_id) do
    results =
      Repo.all(
        from t in LabTest,
          where: t.case_id == ^case_id and t.status in [:resulted, :corrected],
          select: t.result
      )

    cond do
      :positive in results -> :positive
      :negative in results -> :negative
      true -> :none
    end
  end
end
