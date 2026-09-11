defmodule ZamHealthWatch.VaccinationMonitoringTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.VaccinationMonitoringFixtures

  describe "list_vaccination_records/0" do
    test "returns an empty list with no records" do
      assert VaccinationMonitoring.list_vaccination_records() == []
    end

    test "returns every record" do
      a = vaccination_record_fixture()
      b = vaccination_record_fixture()

      assert VaccinationMonitoring.list_vaccination_records() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([a.id, b.id])
    end
  end

  describe "get_vaccination_record!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        VaccinationMonitoring.get_vaccination_record!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the record with the given id" do
      %{id: id} = vaccination_record_fixture()
      assert %VaccinationRecord{id: ^id} = VaccinationMonitoring.get_vaccination_record!(id)
    end
  end

  describe "record_vaccination/1" do
    test "records with valid data" do
      district = district_fixture()
      user = user_fixture()

      assert {:ok, %VaccinationRecord{} = record} =
               VaccinationMonitoring.record_vaccination(%{
                 antigen: :bcg,
                 campaign: "Routine - Sep 2026",
                 doses_administered: 45,
                 target_population: 60,
                 district_id: district.id,
                 reported_by_id: user.id
               })

      assert record.antigen == :bcg
      assert record.campaign == "Routine - Sep 2026"
      assert record.doses_administered == 45
      assert record.target_population == 60
      assert record.district_id == district.id
      assert record.reported_by_id == user.id
    end

    test "requires antigen, campaign, doses_administered, target_population, district_id, and reported_by_id" do
      assert {:error, changeset} = VaccinationMonitoring.record_vaccination(%{})

      assert %{
               antigen: ["can't be blank"],
               campaign: ["can't be blank"],
               doses_administered: ["can't be blank"],
               target_population: ["can't be blank"],
               district_id: ["can't be blank"],
               reported_by_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects a negative doses_administered" do
      district = district_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               VaccinationMonitoring.record_vaccination(%{
                 antigen: :bcg,
                 campaign: "Routine",
                 doses_administered: -1,
                 target_population: 60,
                 district_id: district.id,
                 reported_by_id: user.id
               })

      assert %{doses_administered: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "rejects a zero or negative target_population" do
      district = district_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               VaccinationMonitoring.record_vaccination(%{
                 antigen: :bcg,
                 campaign: "Routine",
                 doses_administered: 10,
                 target_population: 0,
                 district_id: district.id,
                 reported_by_id: user.id
               })

      assert %{target_population: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "rejects a district_id that doesn't reference a real district" do
      user = user_fixture()

      assert {:error, changeset} =
               VaccinationMonitoring.record_vaccination(%{
                 antigen: :bcg,
                 campaign: "Routine",
                 doses_administered: 10,
                 target_population: 20,
                 district_id: Ecto.UUID.generate(),
                 reported_by_id: user.id
               })

      assert %{district_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects a reported_by_id that doesn't reference a real user" do
      district = district_fixture()

      assert {:error, changeset} =
               VaccinationMonitoring.record_vaccination(%{
                 antigen: :bcg,
                 campaign: "Routine",
                 doses_administered: 10,
                 target_population: 20,
                 district_id: district.id,
                 reported_by_id: Ecto.UUID.generate()
               })

      assert %{reported_by_id: ["does not exist"]} = errors_on(changeset)
    end

    test "broadcasts the created record" do
      district = district_fixture()
      user = user_fixture()
      VaccinationMonitoring.subscribe_vaccination_records()

      assert {:ok, record} =
               VaccinationMonitoring.record_vaccination(%{
                 antigen: :bcg,
                 campaign: "Routine",
                 doses_administered: 10,
                 target_population: 20,
                 district_id: district.id,
                 reported_by_id: user.id
               })

      assert_receive {:created, ^record}
    end
  end

  describe "change_vaccination_record/2" do
    test "returns a vaccination record changeset" do
      assert %Ecto.Changeset{} =
               changeset = VaccinationMonitoring.change_vaccination_record(%VaccinationRecord{})

      assert changeset.required == [
               :antigen,
               :campaign,
               :doses_administered,
               :target_population,
               :district_id,
               :reported_by_id
             ]
    end
  end

  describe "VaccinationRecord.coverage_rate/1" do
    test "returns doses_administered / target_population" do
      record = vaccination_record_fixture(%{doses_administered: 40, target_population: 50})
      assert VaccinationRecord.coverage_rate(record) == 0.8
    end

    test "is not capped at 1.0 when doses exceed target (deliberate, logged behavior)" do
      record = vaccination_record_fixture(%{doses_administered: 120, target_population: 100})
      assert VaccinationRecord.coverage_rate(record) == 1.2
    end
  end

  describe "VaccinationRecord.antigen_options/0 and antigen_label/1" do
    test "antigen_options returns every valid antigen with a label" do
      assert {"BCG", :bcg} in VaccinationRecord.antigen_options()
    end

    test "antigen_label looks up the label" do
      assert VaccinationRecord.antigen_label(:opv) == "OPV (Polio)"
    end

    test "antigen_label falls back to humanize for an unmapped value" do
      assert VaccinationRecord.antigen_label(:unknown_antigen) == "Unknown antigen"
    end
  end
end
