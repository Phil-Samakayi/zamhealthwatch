defmodule ZamHealthWatch.PredictiveAnalyticsTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.PredictiveAnalytics
  alias ZamHealthWatch.PredictiveAnalytics.RiskScore

  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures

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

  # weeks_ago 0 lands in the most recent 7-day bucket ("this week");
  # higher numbers land in progressively older buckets. Placed well
  # inside each bucket (mid-week) rather than right on a boundary, same
  # spirit as CaseManagementTest's own boundary test for
  # count_cases_by_facility_between/2, which already covers the edges.
  defp report_case_weeks_ago(facility, weeks_ago) do
    report_case_at(facility, DateTime.add(@now, -(weeks_ago * 7 + 3), :day))
  end

  defp report_case_at(facility, inserted_at) do
    {:ok, case} =
      ZamHealthWatch.CaseManagement.create_case(%{
        disease: :malaria,
        facility_id: facility.id,
        reported_by_id: ZamHealthWatch.AccountsFixtures.user_fixture().id
      })

    case
    |> Ecto.Changeset.change(inserted_at: inserted_at)
    |> ZamHealthWatch.Repo.update!()
  end
end
