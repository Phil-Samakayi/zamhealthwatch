defmodule ZamHealthWatch.HospitalCapacityTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.HospitalCapacity.CapacityReport

  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures

  describe "list_capacity_reports/0" do
    test "returns an empty list with no reports" do
      assert HospitalCapacity.list_capacity_reports() == []
    end

    test "returns every report" do
      a = capacity_report_fixture()
      b = capacity_report_fixture()

      assert HospitalCapacity.list_capacity_reports() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([a.id, b.id])
    end
  end

  describe "get_capacity_report!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        HospitalCapacity.get_capacity_report!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the report with the given id" do
      %{id: id} = capacity_report_fixture()
      assert %CapacityReport{id: ^id} = HospitalCapacity.get_capacity_report!(id)
    end
  end

  describe "record_capacity/1" do
    test "records with valid data" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:ok, %CapacityReport{} = report} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 100,
                 occupied_beds: 60,
                 icu_beds_total: 10,
                 icu_beds_occupied: 5,
                 admissions_today: 12,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert report.total_beds == 100
      assert report.occupied_beds == 60
      assert report.icu_beds_total == 10
      assert report.icu_beds_occupied == 5
      assert report.admissions_today == 12
      assert report.facility_id == facility.id
      assert report.reported_by_id == user.id
    end

    test "requires every field" do
      assert {:error, changeset} = HospitalCapacity.record_capacity(%{})

      assert %{
               total_beds: ["can't be blank"],
               occupied_beds: ["can't be blank"],
               icu_beds_total: ["can't be blank"],
               icu_beds_occupied: ["can't be blank"],
               admissions_today: ["can't be blank"],
               facility_id: ["can't be blank"],
               reported_by_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects a zero or negative total_beds" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 0,
                 occupied_beds: 0,
                 icu_beds_total: 0,
                 icu_beds_occupied: 0,
                 admissions_today: 0,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert %{total_beds: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "rejects a negative occupied_beds" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 100,
                 occupied_beds: -1,
                 icu_beds_total: 0,
                 icu_beds_occupied: 0,
                 admissions_today: 0,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert %{occupied_beds: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "allows occupied_beds to exceed total_beds (deliberate, logged behavior)" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:ok, report} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 100,
                 occupied_beds: 120,
                 icu_beds_total: 10,
                 icu_beds_occupied: 12,
                 admissions_today: 5,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert report.occupied_beds == 120
      assert report.icu_beds_occupied == 12
    end

    test "rejects a facility_id that doesn't reference a real facility" do
      user = user_fixture()

      assert {:error, changeset} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 100,
                 occupied_beds: 50,
                 icu_beds_total: 10,
                 icu_beds_occupied: 5,
                 admissions_today: 5,
                 facility_id: Ecto.UUID.generate(),
                 reported_by_id: user.id
               })

      assert %{facility_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects a reported_by_id that doesn't reference a real user" do
      facility = facility_fixture()

      assert {:error, changeset} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 100,
                 occupied_beds: 50,
                 icu_beds_total: 10,
                 icu_beds_occupied: 5,
                 admissions_today: 5,
                 facility_id: facility.id,
                 reported_by_id: Ecto.UUID.generate()
               })

      assert %{reported_by_id: ["does not exist"]} = errors_on(changeset)
    end

    test "broadcasts the created report" do
      facility = facility_fixture()
      user = user_fixture()
      HospitalCapacity.subscribe_capacity_reports()

      assert {:ok, report} =
               HospitalCapacity.record_capacity(%{
                 total_beds: 100,
                 occupied_beds: 50,
                 icu_beds_total: 10,
                 icu_beds_occupied: 5,
                 admissions_today: 5,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert_receive {:created, ^report}
    end
  end

  describe "change_capacity_report/2" do
    test "returns a capacity report changeset" do
      assert %Ecto.Changeset{} =
               changeset = HospitalCapacity.change_capacity_report(%CapacityReport{})

      assert changeset.required == [
               :total_beds,
               :occupied_beds,
               :icu_beds_total,
               :icu_beds_occupied,
               :admissions_today,
               :facility_id,
               :reported_by_id
             ]
    end
  end

  describe "CapacityReport.bed_occupancy_rate/1" do
    test "returns occupied_beds / total_beds" do
      report = capacity_report_fixture(%{occupied_beds: 40, total_beds: 50})
      assert CapacityReport.bed_occupancy_rate(report) == 0.8
    end

    test "is not capped at 1.0 when occupied exceeds total (deliberate, logged behavior)" do
      report = capacity_report_fixture(%{occupied_beds: 120, total_beds: 100})
      assert CapacityReport.bed_occupancy_rate(report) == 1.2
    end
  end

  describe "CapacityReport.icu_occupancy_rate/1" do
    test "returns icu_beds_occupied / icu_beds_total" do
      report = capacity_report_fixture(%{icu_beds_occupied: 3, icu_beds_total: 4})
      assert CapacityReport.icu_occupancy_rate(report) == 0.75
    end

    test "returns nil when the facility has no ICU beds" do
      report = capacity_report_fixture(%{icu_beds_occupied: 0, icu_beds_total: 0})
      assert CapacityReport.icu_occupancy_rate(report) == nil
    end
  end

  describe "CapacityReport.icu_beds_available/1" do
    test "returns icu_beds_total - icu_beds_occupied" do
      report = capacity_report_fixture(%{icu_beds_total: 10, icu_beds_occupied: 4})
      assert CapacityReport.icu_beds_available(report) == 6
    end

    test "can go negative when ICU occupancy exceeds total (deliberate, logged behavior)" do
      report = capacity_report_fixture(%{icu_beds_total: 10, icu_beds_occupied: 12})
      assert CapacityReport.icu_beds_available(report) == -2
    end
  end

  describe "CapacityReport.capacity_status/1" do
    test "returns :adequate below 80% bed occupancy" do
      report = capacity_report_fixture(%{occupied_beds: 50, total_beds: 100})
      assert CapacityReport.capacity_status(report) == :adequate
    end

    test "returns :near_capacity between 80% and 99% bed occupancy" do
      report = capacity_report_fixture(%{occupied_beds: 85, total_beds: 100})
      assert CapacityReport.capacity_status(report) == :near_capacity
    end

    test "returns :over_capacity at or above 100% bed occupancy" do
      report = capacity_report_fixture(%{occupied_beds: 110, total_beds: 100})
      assert CapacityReport.capacity_status(report) == :over_capacity
    end
  end
end
