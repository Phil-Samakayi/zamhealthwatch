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
end
