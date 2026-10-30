defmodule ZamHealthWatch.LabReportingTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.LabReporting.LabTest

  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.LabReportingFixtures

  describe "list_lab_tests/0" do
    test "returns an empty list with no lab tests" do
      assert LabReporting.list_lab_tests() == []
    end

    test "returns every lab test" do
      a = lab_test_fixture()
      b = lab_test_fixture()

      assert LabReporting.list_lab_tests() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([a.id, b.id])
    end
  end

  describe "list_lab_tests_by_facility/1" do
    import ZamHealthWatch.GeographyFixtures

    test "returns only lab tests for cases at that facility" do
      facility = facility_fixture()
      other_facility = facility_fixture()

      case_at_facility = case_fixture(%{facility_id: facility.id})
      case_elsewhere = case_fixture(%{facility_id: other_facility.id})

      lab_test = lab_test_fixture(%{case_id: case_at_facility.id})
      _other_lab_test = lab_test_fixture(%{case_id: case_elsewhere.id})

      assert LabReporting.list_lab_tests_by_facility(facility.id) == [lab_test]
    end

    test "returns an empty list for a facility with no cases at all" do
      facility = facility_fixture()
      assert LabReporting.list_lab_tests_by_facility(facility.id) == []
    end

    test "returns an empty list for a facility whose cases have no lab tests yet" do
      facility = facility_fixture()
      case_fixture(%{facility_id: facility.id})

      assert LabReporting.list_lab_tests_by_facility(facility.id) == []
    end
  end

  describe "get_lab_test!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        LabReporting.get_lab_test!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the lab test with the given id" do
      %{id: id} = lab_test_fixture()
      assert %LabTest{id: ^id} = LabReporting.get_lab_test!(id)
    end
  end

  describe "request_test/1" do
    test "requests a test with valid data" do
      case_record = case_fixture()
      user = user_fixture()

      assert {:ok, %LabTest{} = lab_test} =
               LabReporting.request_test(%{case_id: case_record.id, requested_by_id: user.id})

      assert lab_test.status == :pending
      assert lab_test.result == nil
      assert lab_test.case_id == case_record.id
      assert lab_test.requested_by_id == user.id
    end

    test "requires case_id and requested_by_id" do
      assert {:error, changeset} = LabReporting.request_test(%{})

      assert %{case_id: ["can't be blank"], requested_by_id: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "rejects a case_id that doesn't reference a real case" do
      user = user_fixture()

      assert {:error, changeset} =
               LabReporting.request_test(%{
                 case_id: Ecto.UUID.generate(),
                 requested_by_id: user.id
               })

      assert %{case_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects a requested_by_id that doesn't reference a real user" do
      case_record = case_fixture()

      assert {:error, changeset} =
               LabReporting.request_test(%{
                 case_id: case_record.id,
                 requested_by_id: Ecto.UUID.generate()
               })

      assert %{requested_by_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "change_lab_test/2" do
    test "returns a lab test changeset" do
      assert %Ecto.Changeset{} = changeset = LabReporting.change_lab_test(%LabTest{})
      assert changeset.required == [:case_id, :requested_by_id]
    end
  end

  describe "record_result/3" do
    setup do
      %{lab_officer: user_fixture() |> set_role(:lab_officer)}
    end

    test "a positive result confirms the linked case and records who entered it", %{
      lab_officer: lab_officer
    } do
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, updated} = LabReporting.record_result(lab_test, :positive, lab_officer)

      assert updated.status == :resulted
      assert updated.result == :positive
      assert updated.resulted_at != nil
      assert updated.resulted_by_id == lab_officer.id
      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "a negative result rules the linked case out (not a case)", %{lab_officer: lab_officer} do
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, updated} = LabReporting.record_result(lab_test, :negative, lab_officer)

      assert updated.result == :negative
      assert CaseManagement.get_case!(case_record.id).status == :not_a_case
    end

    test "an inconclusive result leaves the linked case's status unchanged", %{
      lab_officer: lab_officer
    } do
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, updated} = LabReporting.record_result(lab_test, :inconclusive, lab_officer)

      assert updated.result == :inconclusive
      assert CaseManagement.get_case!(case_record.id).status == :suspected
    end

    test "a positive result reclassifies a case an earlier result ruled out", %{
      lab_officer: lab_officer
    } do
      case_record = case_fixture()
      {:ok, case_record} = CaseManagement.update_case_status(case_record, %{status: :not_a_case})
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, _updated} = LabReporting.record_result(lab_test, :positive, lab_officer)

      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "rejects every role except lab officer" do
      for role <- [nil, :health_worker, :district_officer, :moh_admin] do
        lab_test = lab_test_fixture()
        user = if role, do: user_fixture() |> set_role(role), else: user_fixture()

        assert LabReporting.record_result(lab_test, :positive, user) == {:error, :unauthorized}
        assert LabReporting.get_lab_test!(lab_test.id).status == :pending
      end
    end

    test "rejects re-recording a result for an already-resulted test", %{lab_officer: lab_officer} do
      lab_test = lab_test_fixture()
      {:ok, resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      assert LabReporting.record_result(resulted, :negative, lab_officer) ==
               {:error, :already_resulted}

      assert LabReporting.get_lab_test!(lab_test.id).result == :positive
    end

    test "broadcasts the updated lab test", %{lab_officer: lab_officer} do
      lab_test = lab_test_fixture()
      LabReporting.subscribe_lab_tests()

      {:ok, updated} = LabReporting.record_result(lab_test, :positive, lab_officer)

      assert_receive {:updated, ^updated}
    end
  end

  describe "can_record_results?/1" do
    test "is true only for lab officers" do
      assert LabReporting.can_record_results?(:lab_officer)
      refute LabReporting.can_record_results?(:moh_admin)
      refute LabReporting.can_record_results?(:district_officer)
      refute LabReporting.can_record_results?(:health_worker)
      refute LabReporting.can_record_results?(nil)
    end
  end

  describe "correct_result/4" do
    setup do
      lab_officer = user_fixture() |> set_role(:lab_officer)
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, issued} = LabReporting.record_result(lab_test, :positive, lab_officer)

      %{lab_officer: lab_officer, case_record: case_record, issued: issued}
    end

    test "replaces the result, keeps the original in the history, and reclassifies the case", %{
      lab_officer: lab_officer,
      case_record: case_record,
      issued: issued
    } do
      assert CaseManagement.get_case!(case_record.id).status == :confirmed

      assert {:ok, corrected} =
               LabReporting.correct_result(
                 issued,
                 :negative,
                 "Repeat test on a fresh sample was negative.",
                 lab_officer
               )

      assert corrected.status == :corrected
      assert corrected.result == :negative
      # Who issued the original result, and when, are left as they were.
      assert corrected.resulted_by_id == lab_officer.id
      assert corrected.resulted_at == issued.resulted_at

      assert [correction] = LabReporting.list_corrections_for_lab_test(issued.id)
      assert correction.kind == :corrected
      assert correction.previous_result == :positive
      assert correction.new_result == :negative
      assert correction.reason == "Repeat test on a fresh sample was negative."
      assert correction.corrected_by_id == lab_officer.id

      assert CaseManagement.get_case!(case_record.id).status == :not_a_case
    end

    test "can be corrected again, and the history keeps every step in order", %{
      lab_officer: lab_officer,
      issued: issued
    } do
      {:ok, once} =
        LabReporting.correct_result(issued, :negative, "First repeat test negative.", lab_officer)

      {:ok, _twice} =
        LabReporting.correct_result(
          once,
          :inconclusive,
          "Second repeat test was indeterminate.",
          lab_officer
        )

      assert [first, second] = LabReporting.list_corrections_for_lab_test(issued.id)
      assert {first.previous_result, first.new_result} == {:positive, :negative}
      assert {second.previous_result, second.new_result} == {:negative, :inconclusive}
    end

    test "an MOH admin can correct a result too", %{issued: issued} do
      admin = user_fixture() |> set_role(:moh_admin)

      assert {:ok, _} =
               LabReporting.correct_result(issued, :negative, "Corrected after lab audit.", admin)
    end

    test "refuses every other role", %{issued: issued} do
      for role <- [:health_worker, :district_officer] do
        user = user_fixture() |> set_role(role)

        assert LabReporting.correct_result(issued, :negative, "A long enough reason.", user) ==
                 {:error, :unauthorized}
      end

      assert LabReporting.list_corrections_for_lab_test(issued.id) == []
    end

    test "requires a reason of at least 10 characters, and changes nothing without one", %{
      lab_officer: lab_officer,
      case_record: case_record,
      issued: issued
    } do
      assert {:error, %Ecto.Changeset{} = changeset} =
               LabReporting.correct_result(issued, :negative, "  wrong  ", lab_officer)

      assert %{reason: [_too_short]} = errors_on(changeset)
      assert LabReporting.get_lab_test!(issued.id).result == :positive
      assert LabReporting.list_corrections_for_lab_test(issued.id) == []
      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "refuses a correction to the result the test already has", %{
      lab_officer: lab_officer,
      issued: issued
    } do
      assert LabReporting.correct_result(issued, :positive, "Same result again.", lab_officer) ==
               {:error, :unchanged}
    end

    test "refuses to correct a test with no issued result", %{lab_officer: lab_officer} do
      pending = lab_test_fixture()

      assert LabReporting.correct_result(pending, :negative, "Nothing to correct.", lab_officer) ==
               {:error, :not_correctable}
    end

    test "broadcasts the corrected test", %{lab_officer: lab_officer, issued: issued} do
      LabReporting.subscribe_lab_tests()

      {:ok, corrected} =
        LabReporting.correct_result(issued, :negative, "Repeat test negative.", lab_officer)

      assert_receive {:updated, ^corrected}
    end

    test "a positive on another of the case's tests still confirms it", %{
      lab_officer: lab_officer,
      case_record: case_record,
      issued: issued
    } do
      other = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _} = LabReporting.record_result(other, :positive, lab_officer)

      {:ok, _} = LabReporting.correct_result(issued, :negative, "Repeat test negative.", lab_officer)

      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end
  end

  describe "withdraw_result/3" do
    setup do
      lab_officer = user_fixture() |> set_role(:lab_officer)
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, issued} = LabReporting.record_result(lab_test, :positive, lab_officer)

      %{lab_officer: lab_officer, case_record: case_record, issued: issued}
    end

    test "withdraws the result, records why, and returns the case to suspected", %{
      lab_officer: lab_officer,
      case_record: case_record,
      issued: issued
    } do
      assert {:ok, withdrawn} =
               LabReporting.withdraw_result(issued, "Entered against the wrong case.", lab_officer)

      assert withdrawn.status == :entered_in_error
      # Kept, so the screen can still show what was withdrawn.
      assert withdrawn.result == :positive

      assert [correction] = LabReporting.list_corrections_for_lab_test(issued.id)
      assert correction.kind == :entered_in_error
      assert correction.previous_result == :positive
      assert correction.new_result == nil

      assert CaseManagement.get_case!(case_record.id).status == :suspected
    end

    test "keeps a clinical confirmation when the lab's positive is withdrawn", %{
      lab_officer: lab_officer,
      case_record: case_record,
      issued: issued
    } do
      # Confirmed clinically before the result came in.
      ZamHealthWatch.Repo.update!(
        Ecto.Changeset.change(CaseManagement.get_case!(case_record.id),
          clinically_confirmed_at: DateTime.utc_now(:second)
        )
      )

      {:ok, _} = LabReporting.withdraw_result(issued, "Entered against the wrong case.", lab_officer)

      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "a withdrawn result can't be corrected or withdrawn again", %{
      lab_officer: lab_officer,
      issued: issued
    } do
      {:ok, withdrawn} =
        LabReporting.withdraw_result(issued, "Entered against the wrong case.", lab_officer)

      assert LabReporting.correct_result(withdrawn, :negative, "Trying anyway.", lab_officer) ==
               {:error, :not_correctable}

      assert LabReporting.withdraw_result(withdrawn, "Trying again anyway.", lab_officer) ==
               {:error, :not_correctable}
    end

    test "refuses roles that can't correct results", %{issued: issued} do
      user = user_fixture() |> set_role(:district_officer)

      assert LabReporting.withdraw_result(issued, "A long enough reason.", user) ==
               {:error, :unauthorized}
    end
  end

  describe "can_correct_results?/1" do
    test "is true for lab officers and MOH admins only" do
      assert LabReporting.can_correct_results?(:lab_officer)
      assert LabReporting.can_correct_results?(:moh_admin)
      refute LabReporting.can_correct_results?(:district_officer)
      refute LabReporting.can_correct_results?(:health_worker)
      refute LabReporting.can_correct_results?(nil)
    end
  end

  describe "record_result/3 on a corrected or withdrawn test" do
    test "is refused - a result is issued once, then only corrected" do
      lab_officer = user_fixture() |> set_role(:lab_officer)
      {:ok, issued} = LabReporting.record_result(lab_test_fixture(), :positive, lab_officer)
      {:ok, corrected} = LabReporting.correct_result(issued, :negative, "Repeat negative.", lab_officer)

      assert LabReporting.record_result(corrected, :positive, lab_officer) ==
               {:error, :already_resulted}
    end
  end

  describe "correction notices" do
    setup do
      requester = user_fixture()
      lab_officer = user_fixture() |> set_role(:lab_officer)
      lab_test = lab_test_fixture(%{requested_by_id: requester.id})
      {:ok, issued} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, _corrected} =
        LabReporting.correct_result(issued, :negative, "Repeat test negative.", lab_officer)

      [correction] = LabReporting.list_corrections_for_lab_test(lab_test.id)
      %{requester: requester, lab_officer: lab_officer, correction: correction}
    end

    test "the requester is shown the correction", %{requester: requester, correction: correction} do
      assert [notice] = LabReporting.list_correction_notices(requester.id)
      assert notice.id == correction.id
    end

    test "nobody else is shown it - including whoever made the correction", %{
      lab_officer: lab_officer
    } do
      assert LabReporting.list_correction_notices(user_fixture().id) == []
      assert LabReporting.list_correction_notices(lab_officer.id) == []
    end

    test "acknowledging clears the notice, and doing it twice is harmless", %{
      requester: requester,
      correction: correction
    } do
      assert {:ok, _} = LabReporting.acknowledge_correction(correction.id, requester)
      assert LabReporting.list_correction_notices(requester.id) == []

      assert {:ok, _} = LabReporting.acknowledge_correction(correction.id, requester)
    end

    test "only the requester can acknowledge", %{requester: requester, correction: correction} do
      assert LabReporting.acknowledge_correction(correction.id, user_fixture()) ==
               {:error, :not_requester}

      assert [_still_there] = LabReporting.list_correction_notices(requester.id)
    end

    test "an unknown or malformed id is not found", %{requester: requester} do
      assert LabReporting.acknowledge_correction(Ecto.UUID.generate(), requester) ==
               {:error, :not_found}

      assert LabReporting.acknowledge_correction("not-a-uuid", requester) == {:error, :not_found}
    end

    test "a second correction is a new notice, even after the first was seen", %{
      requester: requester,
      lab_officer: lab_officer,
      correction: correction
    } do
      {:ok, _} = LabReporting.acknowledge_correction(correction.id, requester)
      lab_test = LabReporting.get_lab_test!(correction.lab_test_id)

      {:ok, _} =
        LabReporting.correct_result(lab_test, :inconclusive, "Second repeat indeterminate.", lab_officer)

      assert [notice] = LabReporting.list_correction_notices(requester.id)
      assert notice.new_result == :inconclusive
    end
  end
end
