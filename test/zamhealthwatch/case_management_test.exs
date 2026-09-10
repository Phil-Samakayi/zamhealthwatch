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
  end
end
