defmodule ZamHealthWatch.PredictiveAnalyticsTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.PredictiveAnalytics
  alias ZamHealthWatch.PredictiveAnalytics.{DiseaseTrend, DistrictRisk, ImmunityStatus, RiskScore}

  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures
  import ZamHealthWatch.VaccinationMonitoringFixtures

  # A fixed reference point rather than DateTime.utc_now/0, so every
  # case below lands in a known, predictable one of the four weekly
  # buckets instead of racing the wall clock.
  @now ~U[2026-09-11 00:00:00Z]

  describe "list_risk_scores/1" do
    test "returns an insufficient_data score for a facility with no cases at all" do
      facility = facility_fixture()

      assert [%RiskScore{} = score] = PredictiveAnalytics.list_risk_scores(@now)
      assert score.facility_id == facility.id
      assert score.weekly_counts == [0, 0, 0, 0]
      assert score.recent_count == 0
      assert score.tier == :insufficient_data
    end

    test "returns a stable tier for a flat weekly case count" do
      facility = facility_fixture()

      # One case in each of the four 7-day buckets ending at @now:
      # weeks_ago 3 (oldest) down to weeks_ago 0 (most recent).
      for weeks_ago <- 3..0//-1 do
        report_case_weeks_ago(facility, weeks_ago)
      end

      assert [score] = PredictiveAnalytics.list_risk_scores(@now)
      assert score.weekly_counts == [1, 1, 1, 1]
      assert score.recent_count == 1
      assert score.tier == :stable
      assert_in_delta score.trend_slope, 0.0, 0.001
    end

    test "returns an elevated tier for a clearly rising weekly case count" do
      facility = facility_fixture()

      for weeks_ago <- 3..0//-1, _n <- 1..(4 - weeks_ago) do
        report_case_weeks_ago(facility, weeks_ago)
      end

      assert [score] = PredictiveAnalytics.list_risk_scores(@now)
      # weeks_ago 3 -> 1 case, 2 -> 2 cases, 1 -> 3 cases, 0 -> 4 cases.
      assert score.weekly_counts == [1, 2, 3, 4]
      assert score.recent_count == 4
      assert score.tier == :elevated
      assert score.trend_slope > 0.5
    end

    test "lists every facility, even ones with no cases, sorted by most recent-week cases first" do
      busy = facility_fixture(%{name: "Busy Clinic"})
      quiet = facility_fixture(%{name: "Quiet Clinic"})

      report_case_weeks_ago(busy, 0)
      report_case_weeks_ago(busy, 0)

      assert [first, second] = PredictiveAnalytics.list_risk_scores(@now)
      assert first.facility_id == busy.id
      assert first.recent_count == 2
      assert second.facility_id == quiet.id
      assert second.recent_count == 0
    end

    test "does not count a case reported outside the four-week window" do
      facility = facility_fixture()
      report_case_at(facility, DateTime.add(@now, -40, :day))

      assert [score] = PredictiveAnalytics.list_risk_scores(@now)
      assert score.weekly_counts == [0, 0, 0, 0]
      assert score.tier == :insufficient_data
    end

    test "returns a :no_data capacity_status for a facility with no capacity reports" do
      facility_fixture()

      assert [%RiskScore{capacity_status: :no_data}] = PredictiveAnalytics.list_risk_scores(@now)
    end

    test "surfaces a facility's latest capacity_status alongside its case-trend tier" do
      facility = facility_fixture()

      report =
        capacity_report_fixture(%{
          facility_id: facility.id,
          total_beds: 100,
          occupied_beds: 90
        })

      assert [score] = PredictiveAnalytics.list_risk_scores(@now)
      assert score.capacity_status == CapacityReport.capacity_status(report)
      assert score.capacity_status == :near_capacity
    end

    test "uses only the most recently reported capacity report per facility" do
      facility = facility_fixture()

      older =
        capacity_report_fixture(%{
          facility_id: facility.id,
          total_beds: 100,
          occupied_beds: 20
        })

      older
      |> Ecto.Changeset.change(
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-60, :second)
      )
      |> ZamHealthWatch.Repo.update!()

      capacity_report_fixture(%{
        facility_id: facility.id,
        total_beds: 100,
        occupied_beds: 95
      })

      assert [score] = PredictiveAnalytics.list_risk_scores(@now)
      assert score.capacity_status == :near_capacity
    end
  end

  describe "list_district_risks/1" do
    test "returns a district with no cases as insufficient_data, with no disease trends" do
      district = district_fixture(%{name: "Quiet District"})
      facility_fixture(%{district_id: district.id})

      assert [%DistrictRisk{} = risk] = PredictiveAnalytics.list_district_risks(@now)
      assert risk.district_id == district.id
      assert risk.district_name == "Quiet District"
      assert risk.tier == :insufficient_data
      assert risk.recent_count == 0
      assert risk.diseases == []
    end

    test "adds up the same disease across every facility in the district" do
      district = district_fixture()
      clinic = facility_fixture(%{district_id: district.id})
      hospital = facility_fixture(%{district_id: district.id})

      report_disease_weeks_ago(clinic, :cholera, 1)
      report_disease_weeks_ago(hospital, :cholera, 1)
      report_disease_weeks_ago(hospital, :cholera, 0)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert [%DiseaseTrend{disease: :cholera} = cholera] = risk.diseases
      assert cholera.weekly_counts == [0, 0, 2, 1]
      assert risk.recent_count == 1
    end

    test "trends each disease separately, so a fall in one can't hide a rise in another" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})

      # Cholera rises 1, 2, 3, 4 while malaria falls 4, 3, 2, 1. Added
      # together that's a flat 5 a week - "stable" - which is exactly
      # the misreading per-disease trends exist to prevent.
      for weeks_ago <- 3..0//-1 do
        for _n <- 1..(4 - weeks_ago), do: report_disease_weeks_ago(facility, :cholera, weeks_ago)
        for _n <- 1..(weeks_ago + 1), do: report_disease_weeks_ago(facility, :malaria, weeks_ago)
      end

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert risk.tier == :elevated
      assert risk.recent_count == 5

      assert [cholera, malaria] = risk.diseases

      assert {cholera.disease, cholera.weekly_counts, cholera.tier} ==
               {:cholera, [1, 2, 3, 4], :elevated}

      assert {malaria.disease, malaria.weekly_counts, malaria.tier} ==
               {:malaria, [4, 3, 2, 1], :stable}

      # The per-facility read, which adds diseases together, sees no rise.
      assert [facility_score] = PredictiveAnalytics.list_risk_scores(@now)
      assert facility_score.weekly_counts == [5, 5, 5, 5]
      assert facility_score.tier == :stable
    end

    test "leaves out cases at a facility with no district" do
      district = district_fixture()
      no_district = facility_fixture()
      report_disease_weeks_ago(no_district, :cholera, 0)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert risk.district_id == district.id
      assert risk.diseases == []
    end

    test "does not count a case reported outside the four-week window" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})
      report_case_at(facility, DateTime.add(@now, -40, :day))

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert risk.tier == :insufficient_data
      assert risk.diseases == []
    end

    test "sorts districts most at risk first, then by this week's cases" do
      quiet = district_fixture(%{name: "Quiet"})
      steady = district_fixture(%{name: "Steady"})
      rising = district_fixture(%{name: "Rising"})
      steady_facility = facility_fixture(%{district_id: steady.id})
      rising_facility = facility_fixture(%{district_id: rising.id})

      for weeks_ago <- 3..0//-1 do
        report_disease_weeks_ago(steady_facility, :malaria, weeks_ago)
        report_disease_weeks_ago(steady_facility, :malaria, weeks_ago)

        for _n <- 1..(4 - weeks_ago),
            do: report_disease_weeks_ago(rising_facility, :cholera, weeks_ago)
      end

      assert PredictiveAnalytics.list_district_risks(@now) |> Enum.map(& &1.district_id) ==
               [rising.id, steady.id, quiet.id]
    end
  end

  describe "list_district_risks/1 with vaccination coverage" do
    test "raises measles to high where measles-rubella coverage is below 95%" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})
      report_disease_weeks_ago(facility, :measles, 0)
      coverage(district, 80)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert risk.tier == :high

      assert [%DiseaseTrend{disease: :measles} = measles] = risk.diseases
      assert measles.weekly_counts == [0, 0, 0, 1]
      assert measles.tier == :high

      assert %ImmunityStatus{antigen: :measles_rubella, status: :gap} = measles.escalated_by
      assert_in_delta measles.escalated_by.coverage_rate, 0.8, 0.0001
    end

    test "leaves measles at its trend tier when coverage is 95% or more" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})
      report_disease_weeks_ago(facility, :measles, 0)
      coverage(district, 95)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert [%ImmunityStatus{status: :adequate}] = risk.immunity
      assert [%DiseaseTrend{tier: :stable, escalated_by: nil}] = risk.diseases
      assert risk.tier == :stable
    end

    test "leaves measles at its trend tier when the district has no coverage record" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})
      report_disease_weeks_ago(facility, :measles, 0)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)

      assert [%ImmunityStatus{disease: :measles, status: :no_data, coverage_rate: nil}] =
               risk.immunity

      assert [%DiseaseTrend{tier: :stable, escalated_by: nil}] = risk.diseases
    end

    test "shows a gap without measles cases, but changes no tier - including other diseases'" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})
      report_disease_weeks_ago(facility, :cholera, 0)
      coverage(district, 50)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert [%ImmunityStatus{status: :gap}] = risk.immunity
      assert [%DiseaseTrend{disease: :cholera, tier: :stable, escalated_by: nil}] = risk.diseases
      assert risk.tier == :stable
    end

    test "uses the district's most recent coverage record" do
      district = district_fixture()
      facility = facility_fixture(%{district_id: district.id})
      report_disease_weeks_ago(facility, :measles, 0)

      district
      |> coverage(50)
      |> Ecto.Changeset.change(
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-60)
      )
      |> ZamHealthWatch.Repo.update!()

      coverage(district, 97)

      assert [risk] = PredictiveAnalytics.list_district_risks(@now)
      assert [%ImmunityStatus{status: :adequate}] = risk.immunity
      assert risk.tier == :stable
    end

    test "sorts a high district above an elevated one" do
      elevated = district_fixture(%{name: "Elevated"})
      high = district_fixture(%{name: "High"})
      elevated_facility = facility_fixture(%{district_id: elevated.id})
      high_facility = facility_fixture(%{district_id: high.id})

      for weeks_ago <- 3..0//-1, _n <- 1..(4 - weeks_ago) do
        report_disease_weeks_ago(elevated_facility, :cholera, weeks_ago)
      end

      report_disease_weeks_ago(high_facility, :measles, 0)
      coverage(high, 60)

      assert PredictiveAnalytics.list_district_risks(@now) |> Enum.map(& &1.tier) ==
               [:high, :elevated]
    end
  end

  # A measles-rubella coverage record for `district` at `percent`% of a
  # 100-person target.
  defp coverage(district, percent) do
    vaccination_record_fixture(%{
      district_id: district.id,
      antigen: :measles_rubella,
      doses_administered: percent,
      target_population: 100
    })
  end

  # weeks_ago 0 lands in the most recent 7-day bucket ("this week");
  # higher numbers land in progressively older buckets. Placed well
  # inside each bucket (mid-week) rather than right on a boundary, same
  # spirit as CaseManagementTest's own boundary test for
  # count_cases_by_facility_between/2, which already covers the edges.
  defp report_case_weeks_ago(facility, weeks_ago) do
    report_case_at(facility, DateTime.add(@now, -(weeks_ago * 7 + 3), :day))
  end

  defp report_disease_weeks_ago(facility, disease, weeks_ago) do
    report_case_at(facility, DateTime.add(@now, -(weeks_ago * 7 + 3), :day), disease)
  end

  defp report_case_at(facility, inserted_at, disease \\ :malaria) do
    {:ok, case} =
      ZamHealthWatch.CaseManagement.create_case(%{
        disease: disease,
        facility_id: facility.id,
        reported_by_id: ZamHealthWatch.AccountsFixtures.user_fixture().id
      })

    case
    |> Ecto.Changeset.change(inserted_at: inserted_at)
    |> ZamHealthWatch.Repo.update!()
  end
end
