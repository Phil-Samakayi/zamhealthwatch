defmodule ZamHealthWatch.CaseManagementTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.CaseManagement

  describe "cases" do
    alias ZamHealthWatch.CaseManagement.Case

    import ZamHealthWatch.CaseManagementFixtures
    import ZamHealthWatch.AccountsFixtures, only: [user_fixture: 0]
    import ZamHealthWatch.GeographyFixtures, only: [facility_fixture: 0]

    @invalid_attrs %{disease: nil, facility_id: nil, reported_by_id: nil}

    test "list_cases/0 returns all cases" do
      case = case_fixture()
      assert CaseManagement.list_cases() == [case]
    end

    test "list_cases_by_facility/1 returns only cases at that facility" do
      facility = facility_fixture()
      other_facility = facility_fixture()
      case = case_fixture(%{facility_id: facility.id})
      _other_case = case_fixture(%{facility_id: other_facility.id})

      assert CaseManagement.list_cases_by_facility(facility.id) == [case]
    end

    test "list_cases_by_facility/1 orders by most recently reported first" do
      facility = facility_fixture()
      older = case_fixture(%{facility_id: facility.id})

      # Backdated, not just inserted first - see
      # DrugAvailabilityTest.list_drug_stocks_by_facility/1's own
      # ordering test for why (same-second insert flakiness).
      #
      # `older` is reassigned to `Repo.update!/1`'s own return value,
      # not left pointing at the pre-update struct - the backdate only
      # changes what's in the database; the local variable still holds
      # the original (non-backdated) `inserted_at`/`updated_at` until
      # this reassigns it, which is exactly what the subsequent `==`
      # assertion below compares against.
      older =
        older
        |> Ecto.Changeset.change(
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-60, :second)
        )
        |> ZamHealthWatch.Repo.update!()

      newer = case_fixture(%{facility_id: facility.id})

      assert CaseManagement.list_cases_by_facility(facility.id) == [newer, older]
    end

    test "get_case!/1 returns the case with given id" do
      case = case_fixture()
      assert CaseManagement.get_case!(case.id) == case
    end

    test "create_case/1 with valid data creates a case, starting :suspected" do
      facility = facility_fixture()
      user = user_fixture()

      valid_attrs = %{disease: :cholera, facility_id: facility.id, reported_by_id: user.id}

      assert {:ok, %Case{} = case} = CaseManagement.create_case(valid_attrs)
      assert case.disease == :cholera
      assert case.status == :suspected
      assert case.facility_id == facility.id
      assert case.reported_by_id == user.id
    end

    test "create_case/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = CaseManagement.create_case(@invalid_attrs)
    end

    test "create_case/1 rejects a disease outside the enum" do
      facility = facility_fixture()
      user = user_fixture()

      attrs = %{disease: :flu, facility_id: facility.id, reported_by_id: user.id}
      assert {:error, changeset} = CaseManagement.create_case(attrs)
      assert %{disease: ["is invalid"]} = errors_on(changeset)
    end

    test "create_case/1 rejects a facility_id that doesn't reference a real facility" do
      user = user_fixture()
      attrs = %{disease: :cholera, facility_id: Ecto.UUID.generate(), reported_by_id: user.id}

      assert {:error, changeset} = CaseManagement.create_case(attrs)
      assert %{facility_id: ["does not exist"]} = errors_on(changeset)
    end

    test "change_case/2 returns a case changeset" do
      case = case_fixture()
      assert %Ecto.Changeset{} = CaseManagement.change_case(case)
    end

    test "update_case_status/2 moves a case to :confirmed" do
      case = case_fixture()

      assert {:ok, %Case{} = case} =
               CaseManagement.update_case_status(case, %{status: :confirmed})

      assert case.status == :confirmed
    end

    test "update_case_status/2 rejects a status outside the enum" do
      case = case_fixture()
      assert {:error, changeset} = CaseManagement.update_case_status(case, %{status: :closed})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "change_case_status/2 returns a case changeset" do
      case = case_fixture()
      assert %Ecto.Changeset{} = CaseManagement.change_case_status(case)
    end
  end

  describe "epidemiology aggregates" do
    import ZamHealthWatch.CaseManagementFixtures
    import ZamHealthWatch.GeographyFixtures

    test "count_cases/0 returns 0 with no cases" do
      assert CaseManagement.count_cases() == 0
    end

    test "count_cases/0 counts all reported cases" do
      case_fixture()
      case_fixture()

      assert CaseManagement.count_cases() == 2
    end

    test "count_cases/0 and the other totals exclude cases ruled out as not a case" do
      facility = facility_fixture()
      case_fixture(%{disease: :cholera, facility_id: facility.id})
      ruled_out = case_fixture(%{disease: :cholera, facility_id: facility.id})
      {:ok, _} = CaseManagement.update_case_status(ruled_out, %{status: :not_a_case})

      assert CaseManagement.count_cases() == 1
      assert CaseManagement.count_cases_by_disease() == %{cholera: 1}
      assert CaseManagement.count_cases_by_facility() == %{facility.id => 1}

      assert CaseManagement.count_cases_by_facility_between(
               DateTime.add(DateTime.utc_now(), -3600, :second),
               DateTime.add(DateTime.utc_now(), 3600, :second)
             ) == %{facility.id => 1}
    end

    test "count_cases_by_status/0 still reports ruled-out cases under :not_a_case" do
      case_fixture()
      ruled_out = case_fixture()
      {:ok, _} = CaseManagement.update_case_status(ruled_out, %{status: :not_a_case})

      assert CaseManagement.count_cases_by_status() == %{suspected: 1, not_a_case: 1}
    end

    test "count_cases_by_outcome/0 counts recorded outcomes, omitting cases with none" do
      recovered = case_fixture()
      died = case_fixture()
      _no_outcome = case_fixture()
      {:ok, _} = CaseManagement.record_outcome(recovered, :recovered, recorder(:health_worker))
      {:ok, _} = CaseManagement.record_outcome(died, :died, recorder(:health_worker))

      assert CaseManagement.count_cases_by_outcome() == %{recovered: 1, died: 1}
    end

    test "any_cases?/0 is true even when every case was ruled out" do
      refute CaseManagement.any_cases?()

      ruled_out = case_fixture()
      {:ok, _} = CaseManagement.update_case_status(ruled_out, %{status: :not_a_case})

      assert CaseManagement.any_cases?()
      assert CaseManagement.count_cases() == 0
    end

    test "count_cases_by_disease/0 groups counts by disease, omitting diseases with none" do
      case_fixture(%{disease: :cholera})
      case_fixture(%{disease: :cholera})
      case_fixture(%{disease: :malaria})

      assert CaseManagement.count_cases_by_disease() == %{cholera: 2, malaria: 1}
    end

    test "count_cases_by_disease/0 returns an empty map with no cases" do
      assert CaseManagement.count_cases_by_disease() == %{}
    end

    test "count_cases_by_status/0 groups counts by status, omitting statuses with none" do
      suspected_case = case_fixture()
      confirmed_case = case_fixture()
      {:ok, _} = CaseManagement.update_case_status(confirmed_case, %{status: :confirmed})
      _still_suspected = suspected_case

      assert CaseManagement.count_cases_by_status() == %{suspected: 1, confirmed: 1}
    end

    test "count_cases_by_facility/0 groups counts by facility, omitting facilities with none" do
      facility_a = facility_fixture(%{name: "Clinic A"})
      facility_b = facility_fixture(%{name: "Clinic B"})
      _empty_facility = facility_fixture(%{name: "Clinic C"})

      case_fixture(%{facility_id: facility_a.id})
      case_fixture(%{facility_id: facility_a.id})
      case_fixture(%{facility_id: facility_b.id})

      assert CaseManagement.count_cases_by_facility() == %{
               facility_a.id => 2,
               facility_b.id => 1
             }
    end

    test "count_cases_by_facility_between/2 only counts cases reported inside the window" do
      facility = facility_fixture()

      _before_window = report_case_at(facility, ~U[2026-08-20 00:00:00Z])
      _inside_window_1 = report_case_at(facility, ~U[2026-09-02 00:00:00Z])
      _inside_window_2 = report_case_at(facility, ~U[2026-09-07 23:59:59Z])
      _at_the_boundary_after_window = report_case_at(facility, ~U[2026-09-08 00:00:00Z])

      assert CaseManagement.count_cases_by_facility_between(
               ~U[2026-09-01 00:00:00Z],
               ~U[2026-09-08 00:00:00Z]
             ) == %{facility.id => 2}
    end

    test "count_cases_by_facility_between/2 returns an empty map when nothing falls in the window" do
      facility_fixture()

      assert CaseManagement.count_cases_by_facility_between(
               ~U[2026-01-01 00:00:00Z],
               ~U[2026-01-08 00:00:00Z]
             ) == %{}
    end

    test "count_cases_by_facility_and_disease_between/2 groups by facility and disease, skipping ruled-out cases" do
      facility = facility_fixture()
      other_facility = facility_fixture()

      case_fixture(%{facility_id: facility.id, disease: :cholera})
      case_fixture(%{facility_id: facility.id, disease: :cholera})
      case_fixture(%{facility_id: facility.id, disease: :malaria})
      case_fixture(%{facility_id: other_facility.id, disease: :cholera})

      ruled_out = case_fixture(%{facility_id: facility.id, disease: :malaria})
      {:ok, _} = CaseManagement.update_case_status(ruled_out, %{status: :not_a_case})

      assert CaseManagement.count_cases_by_facility_and_disease_between(
               DateTime.add(DateTime.utc_now(), -3600, :second),
               DateTime.add(DateTime.utc_now(), 3600, :second)
             ) == %{
               {facility.id, :cholera} => 2,
               {facility.id, :malaria} => 1,
               {other_facility.id, :cholera} => 1
             }
    end

    test "count_cases_by_facility_and_disease_between/2 only counts cases reported inside the window" do
      facility = facility_fixture()

      _before_window = report_case_at(facility, ~U[2026-08-20 00:00:00Z])
      _inside_window = report_case_at(facility, ~U[2026-09-02 00:00:00Z])
      _at_the_boundary_after_window = report_case_at(facility, ~U[2026-09-08 00:00:00Z])

      assert CaseManagement.count_cases_by_facility_and_disease_between(
               ~U[2026-09-01 00:00:00Z],
               ~U[2026-09-08 00:00:00Z]
             ) == %{{facility.id, :malaria} => 1}
    end

    defp report_case_at(facility, inserted_at) do
      case = case_fixture(%{facility_id: facility.id})

      case
      |> Ecto.Changeset.change(inserted_at: inserted_at)
      |> ZamHealthWatch.Repo.update!()
    end
  end

  describe "status transitions" do
    import ZamHealthWatch.CaseManagementFixtures

    test "next_status/1 moves :suspected to :confirmed" do
      assert CaseManagement.next_status(:suspected) == :confirmed
    end

    test "next_status/1 has no manual step after :confirmed" do
      assert CaseManagement.next_status(:confirmed) == nil
    end

    test "next_status/1 has no manual step from :not_a_case" do
      assert CaseManagement.next_status(:not_a_case) == nil
    end

    test "advance_case_status/2 moves a :suspected case to :confirmed when a role is assigned" do
      case = case_fixture()

      assert {:ok, updated_case} = CaseManagement.advance_case_status(case, :health_worker)
      assert updated_case.status == :confirmed
    end

    test "advance_case_status/2 records when the case was confirmed clinically" do
      case = case_fixture()
      assert case.clinically_confirmed_at == nil

      {:ok, updated_case} = CaseManagement.advance_case_status(case, :health_worker)

      assert updated_case.clinically_confirmed_at != nil
    end

    test "advance_case_status/2 rejects a nil role" do
      case = case_fixture()

      assert CaseManagement.advance_case_status(case, nil) == {:error, :unauthorized}
      assert CaseManagement.get_case!(case.id).status == :suspected
    end

    test "advance_case_status/2 rejects a case with no next status, regardless of role" do
      case = case_fixture()
      {:ok, confirmed_case} = CaseManagement.update_case_status(case, %{status: :confirmed})

      assert CaseManagement.advance_case_status(confirmed_case, :district_officer) ==
               {:error, :no_next_status}
    end
  end

  describe "record_outcome/3" do
    import ZamHealthWatch.CaseManagementFixtures

    test "records an outcome and stamps outcome_at" do
      case = case_fixture()

      recorder = recorder(:health_worker)

      assert {:ok, updated} = CaseManagement.record_outcome(case, :recovered, recorder)
      assert updated.outcome == :recovered
      assert updated.outcome_at != nil
      assert updated.outcome_recorded_by_id == recorder.id
      assert updated.status == :suspected
    end

    test "works on a confirmed case without changing its classification" do
      case = case_fixture()
      {:ok, confirmed} = CaseManagement.update_case_status(case, %{status: :confirmed})

      assert {:ok, updated} =
               CaseManagement.record_outcome(confirmed, :died, recorder(:moh_admin))

      assert updated.outcome == :died
      assert updated.status == :confirmed
    end

    test "rejects a nil role" do
      case = case_fixture()

      assert CaseManagement.record_outcome(case, :recovered, recorder(nil)) ==
               {:error, :unauthorized}

      assert CaseManagement.get_case!(case.id).outcome == nil
    end

    test "rejects a case ruled out as not a case" do
      case = case_fixture()
      {:ok, ruled_out} = CaseManagement.update_case_status(case, %{status: :not_a_case})

      assert CaseManagement.record_outcome(ruled_out, :died, recorder(:health_worker)) ==
               {:error, :not_a_case}
    end

    test "won't overwrite an outcome that's already recorded" do
      case = case_fixture()
      {:ok, recovered} = CaseManagement.record_outcome(case, :recovered, recorder(:health_worker))

      assert CaseManagement.record_outcome(recovered, :died, recorder(:health_worker)) ==
               {:error, :outcome_already_recorded}

      assert CaseManagement.get_case!(case.id).outcome == :recovered
    end

    test "rejects a value outside the enum" do
      case = case_fixture()

      assert {:error, changeset} =
               CaseManagement.record_outcome(case, :closed, recorder(:health_worker))

      assert %{outcome: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "correct_outcome/4 and withdraw_outcome/3" do
    import ZamHealthWatch.CaseManagementFixtures

    alias ZamHealthWatch.CaseManagement.OutcomeCorrection

    @reason "Patient was discharged home alive; death recorded in error."

    setup do
      recorder = recorder(:health_worker)
      {:ok, died} = CaseManagement.record_outcome(case_fixture(), :died, recorder)
      %{died: died, recorder: recorder, officer: recorder(:district_officer)}
    end

    test "changes the outcome and records what it was, why, and who changed it", %{
      died: died,
      recorder: recorder,
      officer: officer
    } do
      CaseManagement.subscribe_cases()

      assert {:ok, corrected} = CaseManagement.correct_outcome(died, :recovered, @reason, officer)
      assert corrected.outcome == :recovered
      # The original entry's author and time stay as they were.
      assert corrected.outcome_recorded_by_id == recorder.id
      assert corrected.outcome_at == died.outcome_at

      assert [%OutcomeCorrection{} = correction] =
               CaseManagement.list_outcome_corrections_for_case(died.id)

      assert correction.kind == :corrected
      assert {correction.previous_outcome, correction.new_outcome} == {:died, :recovered}
      assert correction.reason == @reason
      assert correction.corrected_by_id == officer.id

      case_id = died.id
      assert_receive {:updated, %{id: ^case_id, outcome: :recovered}}
    end

    test "removes an outcome entered in error, so a new one can be recorded", %{
      died: died,
      officer: officer
    } do
      assert {:ok, withdrawn} = CaseManagement.withdraw_outcome(died, @reason, officer)
      assert withdrawn.outcome == nil
      assert withdrawn.outcome_at == nil
      assert withdrawn.outcome_recorded_by_id == nil

      assert [
               %OutcomeCorrection{
                 kind: :entered_in_error,
                 previous_outcome: :died,
                 new_outcome: nil
               }
             ] = CaseManagement.list_outcome_corrections_for_case(died.id)

      assert {:ok, %{outcome: :recovered}} =
               CaseManagement.record_outcome(withdrawn, :recovered, recorder(:health_worker))
    end

    test "only district officers and MOH admins can correct", %{died: died} do
      for role <- [:health_worker, :lab_officer, nil] do
        assert CaseManagement.correct_outcome(died, :recovered, @reason, recorder(role)) ==
                 {:error, :unauthorized}

        assert CaseManagement.withdraw_outcome(died, @reason, recorder(role)) ==
                 {:error, :unauthorized}
      end

      assert {:ok, _} =
               CaseManagement.correct_outcome(died, :recovered, @reason, recorder(:moh_admin))

      assert CaseManagement.can_correct_outcomes?(:district_officer)
      refute CaseManagement.can_correct_outcomes?(:health_worker)
    end

    test "refuses a case with no outcome, and a correction to the same outcome", %{
      died: died,
      officer: officer
    } do
      assert CaseManagement.correct_outcome(case_fixture(), :died, @reason, officer) ==
               {:error, :no_outcome}

      assert CaseManagement.withdraw_outcome(case_fixture(), @reason, officer) ==
               {:error, :no_outcome}

      assert CaseManagement.correct_outcome(died, :died, @reason, officer) == {:error, :unchanged}
    end

    test "requires a reason of at least 10 characters, and changes nothing without one", %{
      died: died,
      officer: officer
    } do
      assert {:error, changeset} =
               CaseManagement.correct_outcome(died, :recovered, " wrong ", officer)

      assert %{reason: [_too_short]} = errors_on(changeset)

      assert {:error, _changeset} = CaseManagement.withdraw_outcome(died, "", officer)

      assert CaseManagement.get_case!(died.id).outcome == :died
      assert CaseManagement.list_outcome_corrections_for_case(died.id) == []
    end

    test "rejects an outcome outside the enum, changing nothing", %{died: died, officer: officer} do
      assert {:error, changeset} = CaseManagement.correct_outcome(died, :closed, @reason, officer)
      assert %{new_outcome: ["is invalid"]} = errors_on(changeset)
      assert CaseManagement.get_case!(died.id).outcome == :died
    end

    test "a correction can be corrected again; the history lists both, newest first", %{
      died: died,
      officer: officer
    } do
      {:ok, recovered} = CaseManagement.correct_outcome(died, :recovered, @reason, officer)

      {:ok, _died_again} =
        CaseManagement.correct_outcome(
          recovered,
          :died,
          "Hospital records confirm the patient died on the ward.",
          officer
        )

      assert [newest, oldest] = CaseManagement.list_outcome_corrections_for_case(died.id)
      assert {newest.previous_outcome, newest.new_outcome} == {:recovered, :died}
      assert {oldest.previous_outcome, oldest.new_outcome} == {:died, :recovered}
    end

    test "outcome counts and the corrected-case list follow corrections", %{
      died: died,
      officer: officer
    } do
      assert CaseManagement.count_cases_by_outcome() == %{died: 1}
      assert CaseManagement.list_outcome_corrected_case_ids() == MapSet.new()

      {:ok, _} = CaseManagement.correct_outcome(died, :recovered, @reason, officer)

      assert CaseManagement.count_cases_by_outcome() == %{recovered: 1}
      assert CaseManagement.list_outcome_corrected_case_ids() == MapSet.new([died.id])
    end
  end

  describe "classification_for/2" do
    @clinical ~U[2026-10-01 09:00:00Z]

    test "a positive verdict confirms, with or without a clinical confirmation" do
      assert CaseManagement.classification_for(:positive, nil) == :confirmed
      assert CaseManagement.classification_for(:positive, @clinical) == :confirmed
    end

    test "a negative verdict rules the case out, even over a clinical confirmation" do
      assert CaseManagement.classification_for(:negative, nil) == :not_a_case
      assert CaseManagement.classification_for(:negative, @clinical) == :not_a_case
    end

    test "with no conclusive verdict, a clinical confirmation stands" do
      assert CaseManagement.classification_for(:none, @clinical) == :confirmed
    end

    test "with no conclusive verdict and no clinical confirmation, the case is suspected" do
      assert CaseManagement.classification_for(:none, nil) == :suspected
    end
  end

  describe "apply_lab_verdict/2" do
    import ZamHealthWatch.CaseManagementFixtures

    test "updates the classification and broadcasts when it changes" do
      case = case_fixture()
      CaseManagement.subscribe_cases()

      assert {:ok, updated} = CaseManagement.apply_lab_verdict(case, :negative)
      assert updated.status == :not_a_case
      assert_receive {:updated, ^updated}
    end

    test "writes and broadcasts nothing when the classification is already right" do
      case = case_fixture()
      CaseManagement.subscribe_cases()

      assert {:ok, ^case} = CaseManagement.apply_lab_verdict(case, :none)

      # Matched on this case's id: the "cases" topic is shared with any
      # concurrently running async test that reports a case.
      case_id = case.id
      refute_receive {:updated, %{id: ^case_id}}
    end

    test "returns a clinically confirmed case to confirmed when the lab verdict is withdrawn" do
      case = case_fixture()
      {:ok, confirmed} = CaseManagement.advance_case_status(case, :health_worker)
      {:ok, ruled_out} = CaseManagement.apply_lab_verdict(confirmed, :negative)
      assert ruled_out.status == :not_a_case

      assert {:ok, restored} = CaseManagement.apply_lab_verdict(ruled_out, :none)
      assert restored.status == :confirmed
    end
  end

  describe "reclassification broadcasts" do
    import ZamHealthWatch.CaseManagementFixtures

    test "broadcast the previous status when a lab verdict changes the classification" do
      case = case_fixture()
      CaseManagement.subscribe_reclassifications()

      {:ok, updated} = CaseManagement.apply_lab_verdict(case, :negative)

      assert_receive {:reclassified, ^updated, :suspected}
    end

    test "broadcast when a person confirms a case" do
      case = case_fixture()
      CaseManagement.subscribe_reclassifications()

      {:ok, confirmed} = CaseManagement.advance_case_status(case, :health_worker)

      assert_receive {:reclassified, ^confirmed, :suspected}
    end

    test "aren't sent when the classification doesn't change" do
      case = case_fixture()
      CaseManagement.subscribe_reclassifications()

      {:ok, _same} = CaseManagement.update_case_status(case, %{status: :suspected})

      case_id = case.id
      refute_receive {:reclassified, %{id: ^case_id}, _}
    end
  end

  # Who records or corrects an outcome: a real user (the column has a
  # foreign key) holding `role`.
  defp recorder(role) do
    %{id: ZamHealthWatch.AccountsFixtures.user_fixture().id, role: role}
  end
end
