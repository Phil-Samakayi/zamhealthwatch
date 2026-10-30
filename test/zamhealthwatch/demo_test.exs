defmodule ZamHealthWatch.DemoTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Demo
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.PredictiveAnalytics
  alias ZamHealthWatch.VaccinationMonitoring

  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.GeographyFixtures

  # The same reference facilities/districts priv/repo/seeds.exs creates -
  # Demo looks them up by code and name, so the tests need the real ones.
  defp seed_reference_data(_context) do
    lusaka = district_fixture(%{name: "Lusaka", province: "Lusaka"})
    ndola = district_fixture(%{name: "Ndola", province: "Copperbelt"})
    monze = district_fixture(%{name: "Monze", province: "Southern"})

    facilities = %{
      "UTH" => facility_fixture(%{name: "University Teaching Hospital", code: "UTH", district_id: lusaka.id}),
      "KBW" => facility_fixture(%{name: "Kabwata Clinic", code: "KBW", district_id: lusaka.id}),
      "NTH" => facility_fixture(%{name: "Ndola Teaching Hospital", code: "NTH", district_id: ndola.id}),
      "MMH" => facility_fixture(%{name: "Monze Mission Hospital", code: "MMH", district_id: monze.id})
    }

    %{facilities: facilities}
  end

  describe "ensure_accounts!/0" do
    setup :seed_reference_data

    test "creates one confirmed, password-login account per role", %{facilities: facilities} do
      Demo.ensure_accounts!()

      for %{email: email, role: role} <- Demo.accounts() do
        user = Accounts.get_user_by_email_and_password(email, Demo.password())
        assert user, "expected #{email} to log in with the demo password"
        assert user.role == role
        assert user.confirmed_at
      end

      worker = Accounts.get_user_by_email("health.worker@example.com")
      assert worker.facility_id == facilities["KBW"].id
    end

    test "resets a demo account's role and password back to the published ones" do
      Demo.ensure_accounts!()
      admin = Accounts.get_user_by_email("moh.admin@example.com")

      {:ok, admin} = Accounts.assign_user_role(admin, %{role: :health_worker})
      {:ok, _} = Accounts.update_user_password(admin, %{password: "a different password"})

      Demo.ensure_accounts!()

      reset = Accounts.get_user_by_email_and_password("moh.admin@example.com", Demo.password())
      assert reset.role == :moh_admin
    end

    test "is idempotent - running it twice doesn't create duplicates" do
      Demo.ensure_accounts!()
      Demo.ensure_accounts!()

      demo_emails = Enum.map(Demo.accounts(), & &1.email)
      assert Accounts.list_users() |> Enum.count(&(&1.email in demo_emails)) == 3
    end
  end

  describe "ensure_accounts!/0 without reference data" do
    test "raises a clear error if the demo health worker's facility doesn't exist" do
      assert_raise RuntimeError, ~r/Demo facility KBW is missing/, fn ->
        Demo.ensure_accounts!()
      end
    end
  end

  describe "seed_activity!/1" do
    setup :seed_reference_data

    setup do
      Demo.ensure_accounts!()
      :ok
    end

    test "seeds cases, lab tests, stock, capacity, and coverage into an empty database" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert Demo.seed_activity!(now) == :seeded

      # 22 reports, one of them ruled out by a negative lab result.
      assert CaseManagement.count_cases() == 21
      assert length(LabReporting.list_lab_tests()) == 4
      assert length(DrugAvailability.list_drug_stocks()) == 8
      assert length(HospitalCapacity.list_capacity_reports()) == 4
      assert length(VaccinationMonitoring.list_vaccination_records()) == 4

      assert CaseManagement.count_cases_by_status() |> Map.values() |> Enum.sum() == 22

      statuses = CaseManagement.count_cases_by_status()
      assert statuses[:suspected] > 0
      assert statuses[:confirmed] > 0
      assert statuses[:not_a_case] == 1

      assert CaseManagement.count_cases_by_outcome() == %{died: 1, recovered: 2}
    end

    test "shapes the risk trend: Kabwata elevated, UTH stable, Monze no data", %{
      facilities: facilities
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Demo.seed_activity!(now)

      scores = now |> PredictiveAnalytics.list_risk_scores() |> Map.new(&{&1.facility_id, &1})

      # Kabwata had 1, 2, 3, 5 reports, but one week-2 report was ruled
      # out by a negative lab result - and ruled-out reports don't count.
      assert scores[facilities["KBW"].id].weekly_counts == [1, 1, 3, 5]
      assert scores[facilities["KBW"].id].tier == :elevated
      assert scores[facilities["UTH"].id].tier == :stable
      assert scores[facilities["MMH"].id].tier == :insufficient_data
    end

    test "does nothing to a database that already has cases", %{facilities: facilities} do
      case_fixture(%{facility_id: facilities["UTH"].id})

      assert Demo.seed_activity!() == :skipped
      assert CaseManagement.count_cases() == 1
    end
  end
end
