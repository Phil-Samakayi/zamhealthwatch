defmodule ZamHealthWatch.NationalReportingTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.NationalReporting
  alias ZamHealthWatch.NationalReporting.FacilitySummary

  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures
  import ZamHealthWatch.LabReportingFixtures
  import ZamHealthWatch.VaccinationMonitoringFixtures

  describe "facility_summary/1" do
    test "returns a zeroed-out summary for a facility with no activity at all" do
      facility = facility_fixture()

      assert [%FacilitySummary{} = summary] = NationalReporting.facility_summary()
      assert summary.facility_id == facility.id
      assert summary.facility_name == facility.name
      assert summary.district_name == "-"
      assert summary.cases_by_status == %{}
      assert summary.cases_by_outcome == %{}
      assert summary.lab_tests_by_status == %{}
      assert summary.drug_stock_count == 0
      assert summary.drug_shortage_count == 0
      assert summary.risk.tier == :insufficient_data
      assert summary.risk.capacity_status == :no_data
    end

    test "looks the facility's district name up from its own district_id" do
      district = district_fixture(%{name: "Lusaka"})
      facility_fixture(%{district_id: district.id})

      assert [summary] = NationalReporting.facility_summary()
      assert summary.district_name == "Lusaka"
    end

    test "folds case counts in by status" do
      facility = facility_fixture()
      case_fixture(%{facility_id: facility.id, disease: :cholera})
      confirmed = case_fixture(%{facility_id: facility.id, disease: :malaria})
      ZamHealthWatch.CaseManagement.update_case_status(confirmed, %{status: :confirmed})

      assert [summary] = NationalReporting.facility_summary()
      assert summary.cases_by_status == %{suspected: 1, confirmed: 1}
    end

    test "counts ruled-out reports and deaths separately from the case total" do
      facility = facility_fixture()
      died = case_fixture(%{facility_id: facility.id})
      {:ok, _} = ZamHealthWatch.CaseManagement.record_outcome(died, :died, :health_worker)
      ruled_out = case_fixture(%{facility_id: facility.id})
      ZamHealthWatch.CaseManagement.update_case_status(ruled_out, %{status: :not_a_case})

      assert [summary] = NationalReporting.facility_summary()
      assert FacilitySummary.case_total(summary) == 1
      assert summary.cases_by_status[:not_a_case] == 1
      assert summary.cases_by_outcome == %{died: 1}
    end

    test "folds lab test counts in by status" do
      facility = facility_fixture()
      case_record = case_fixture(%{facility_id: facility.id})
      pending = lab_test_fixture(%{case_id: case_record.id})
      lab_test_fixture(%{case_id: case_record.id})
      lab_officer =
        ZamHealthWatch.AccountsFixtures.user_fixture()
        |> ZamHealthWatch.AccountsFixtures.set_role(:lab_officer)
      {:ok, _} = ZamHealthWatch.LabReporting.record_result(pending, :positive, lab_officer)

      assert [summary] = NationalReporting.facility_summary()
      assert summary.lab_tests_by_status == %{pending: 1, resulted: 1}
    end

    test "counts drug stock records and flags shortages" do
      facility = facility_fixture()
      drug_stock_fixture(%{facility_id: facility.id, quantity_on_hand: 10, reorder_level: 50})
      drug_stock_fixture(%{facility_id: facility.id, quantity_on_hand: 60, reorder_level: 50})

      assert [summary] = NationalReporting.facility_summary()
      assert summary.drug_stock_count == 2
      assert summary.drug_shortage_count == 1
    end

    test "surfaces the facility's risk tier and hospital capacity status" do
      facility = facility_fixture()
      capacity_report_fixture(%{facility_id: facility.id, total_beds: 100, occupied_beds: 95})

      assert [summary] = NationalReporting.facility_summary()
      assert summary.risk.capacity_status == :near_capacity
    end

    test "lists every facility, even ones with no activity" do
      facility_fixture(%{name: "Busy Clinic"})
      facility_fixture(%{name: "Quiet Clinic"})

      assert length(NationalReporting.facility_summary()) == 2
    end
  end

  describe "vaccination_coverage/0" do
    test "returns an empty list when there are no vaccination records" do
      assert NationalReporting.vaccination_coverage() == []
    end

    test "pairs each record with its district's name" do
      district = district_fixture(%{name: "Ndola"})
      record = vaccination_record_fixture(%{district_id: district.id, antigen: :bcg})

      assert [{^record, "Ndola"}] = NationalReporting.vaccination_coverage()
    end

    test "returns one pair per record, across different districts" do
      lusaka = district_fixture(%{name: "Lusaka"})
      ndola = district_fixture(%{name: "Ndola"})
      vaccination_record_fixture(%{district_id: lusaka.id})
      vaccination_record_fixture(%{district_id: ndola.id})

      pairs = NationalReporting.vaccination_coverage()
      assert length(pairs) == 2
      assert Enum.any?(pairs, fn {_record, name} -> name == "Lusaka" end)
      assert Enum.any?(pairs, fn {_record, name} -> name == "Ndola" end)
    end
  end

  describe "export_csv/1" do
    test "includes the facility rollup header and one row per facility" do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      case_fixture(%{facility_id: facility.id, disease: :cholera})

      csv = NationalReporting.export_csv() |> IO.iodata_to_binary()

      assert csv =~
               "Facility,District,Cases (suspected),Cases (confirmed),Cases (total)," <>
                 "Ruled out (not a case),Deaths,Lab tests (pending),Lab tests (resulted)," <>
                 "Drug stock records," <>
                 "Drug stock shortages,Hospital capacity status,Risk tier,Case trend (4wk slope)"

      # One case reported just now lands in the most recent weekly
      # bucket, so the four-week counts are [0, 0, 0, 1] - a real (if
      # small) trend, not :insufficient_data (that tier is only for a
      # facility with zero cases across all four weeks). Least-squares
      # slope over [0, 0, 0, 1] is 0.3, below PredictiveAnalytics'
      # 0.5 "elevated" threshold, so the tier reads as Stable.
      assert csv =~ "Kabwata Clinic,-,1,0,1,0,0,0,0,0,0,No data,Stable,0.3\r\n"
    end

    test "includes a second, district-grain vaccination coverage table" do
      district = district_fixture(%{name: "Ndola"})
      vaccination_record_fixture(%{district_id: district.id, antigen: :bcg, campaign: "Routine"})

      csv = NationalReporting.export_csv() |> IO.iodata_to_binary()

      assert csv =~ "District,Antigen,Campaign,Doses administered,Target population,Coverage"
      assert csv =~ "Ndola,BCG,Routine,"
    end

    test "quotes a field that contains a comma" do
      district = district_fixture()
      vaccination_record_fixture(%{district_id: district.id, campaign: "Routine, catch-up"})

      csv = NationalReporting.export_csv() |> IO.iodata_to_binary()

      assert csv =~ "\"Routine, catch-up\""
    end
  end
end
