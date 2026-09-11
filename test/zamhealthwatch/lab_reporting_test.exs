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
    test "a positive result confirms the linked case" do
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, updated} = LabReporting.record_result(lab_test, :positive, :health_worker)

      assert updated.status == :resulted
      assert updated.result == :positive
      assert updated.resulted_at != nil
      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "a negative result resolves the linked case" do
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, updated} = LabReporting.record_result(lab_test, :negative, :district_officer)

      assert updated.result == :negative
      assert CaseManagement.get_case!(case_record.id).status == :resolved
    end

    test "an inconclusive result leaves the linked case's status unchanged" do
      case_record = case_fixture()
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, updated} = LabReporting.record_result(lab_test, :inconclusive, :moh_admin)

      assert updated.result == :inconclusive
      assert CaseManagement.get_case!(case_record.id).status == :suspected
    end

    test "a positive result reopens an already-resolved case (deliberate, logged limitation)" do
      case_record = case_fixture()
      {:ok, case_record} = CaseManagement.update_case_status(case_record, %{status: :resolved})
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      assert {:ok, _updated} = LabReporting.record_result(lab_test, :positive, :health_worker)

      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "rejects a nil role" do
      lab_test = lab_test_fixture()

      assert LabReporting.record_result(lab_test, :positive, nil) == {:error, :unauthorized}
      assert LabReporting.get_lab_test!(lab_test.id).status == :pending
    end

    test "rejects re-recording a result for an already-resulted test" do
      lab_test = lab_test_fixture()
      {:ok, resulted} = LabReporting.record_result(lab_test, :positive, :health_worker)

      assert LabReporting.record_result(resulted, :negative, :health_worker) ==
               {:error, :already_resulted}

      assert LabReporting.get_lab_test!(lab_test.id).result == :positive
    end

    test "broadcasts the updated lab test" do
      lab_test = lab_test_fixture()
      LabReporting.subscribe_lab_tests()

      {:ok, updated} = LabReporting.record_result(lab_test, :positive, :health_worker)

      assert_receive {:updated, ^updated}
    end
  end
end
