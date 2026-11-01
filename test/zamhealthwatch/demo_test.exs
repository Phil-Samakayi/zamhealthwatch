defmodule ZamHealthWatch.DemoTest do
  use ZamHealthWatch.DataCase
  use Oban.Testing, repo: ZamHealthWatch.Repo

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Demo
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.PredictiveAnalytics
  alias ZamHealthWatch.PublicAlerts
  alias ZamHealthWatch.PublicAlerts.AlertWorker
  alias ZamHealthWatch.VaccinationMonitoring

  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.PublicAlertsFixtures

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
      assert Accounts.list_users() |> Enum.count(&(&1.email in demo_emails)) ==
               length(Demo.accounts())
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

      # 24 reports, one of them ruled out by a negative lab result.
      assert CaseManagement.count_cases() == 23
      lab_tests = LabReporting.list_lab_tests()
      assert length(lab_tests) == 4

      # One demo result was issued positive, then corrected to negative.
      assert [correction] = LabReporting.list_corrections()
      assert {correction.previous_result, correction.new_result} == {:positive, :negative}

      # Every demo result is entered by the demo lab officer, the only
      # role allowed to since Iteration 15.
      lab_officer = Accounts.get_user_by_email("lab.officer@example.com")

      assert lab_tests
             |> Enum.filter(&(&1.status in [:resulted, :corrected]))
             |> Enum.all?(&(&1.resulted_by_id == lab_officer.id))
      assert length(DrugAvailability.list_drug_stocks()) == 8
      assert length(HospitalCapacity.list_capacity_reports()) == 4
      assert length(VaccinationMonitoring.list_vaccination_records()) == 4

      assert CaseManagement.count_cases_by_status() |> Map.values() |> Enum.sum() == 24

      statuses = CaseManagement.count_cases_by_status()
      assert statuses[:suspected] > 0
      assert statuses[:confirmed] > 0
      assert statuses[:not_a_case] == 1

      # Two recoveries, one death, and one death corrected to a recovery.
      assert CaseManagement.count_cases_by_outcome() == %{died: 1, recovered: 3}
      assert [corrected_id] = MapSet.to_list(CaseManagement.list_outcome_corrected_case_ids())

      assert [%{previous_outcome: :died, new_outcome: :recovered}] =
               CaseManagement.list_outcome_corrections_for_case(corrected_id)
    end

    test "shapes the facility risk trend: Kabwata elevated, UTH and Monze stable", %{
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
      assert scores[facilities["MMH"].id].weekly_counts == [0, 0, 1, 1]
      assert scores[facilities["MMH"].id].tier == :stable
    end

    test "raises supply alerts only where the short medicine is needed" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Demo.seed_activity!(now)

      # Kabwata's cholera outbreak with ORS and IV fluids short, and UTH's
      # typhoid case with ceftriaxone short. Monze's artemether-lumefantrine
      # shortage stays quiet: its only malaria case is six weeks old.
      assert now
             |> PredictiveAnalytics.list_supply_alerts()
             |> Enum.map(&{&1.facility_name, &1.disease, &1.medicine, &1.tier}) == [
               {"Kabwata Clinic", :cholera, :iv_fluids, :elevated},
               {"Kabwata Clinic", :cholera, :ors, :elevated},
               {"University Teaching Hospital", :typhoid, :ceftriaxone, :stable}
             ]
    end

    test "shapes the district risk: Monze high from its measles immunity gap, Lusaka elevated, Ndola stable" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Demo.seed_activity!(now)

      risks = PredictiveAnalytics.list_district_risks(now)

      assert Enum.map(risks, &{&1.district_name, &1.tier}) ==
               [{"Monze", :high}, {"Lusaka", :elevated}, {"Ndola", :stable}]

      [monze, lusaka, ndola] = risks
      assert [%{disease: :measles, escalated_by: %{status: :gap}}] = monze.diseases
      assert [%{disease: :cholera} | _] = lusaka.diseases
      assert [%{status: :gap}] = lusaka.immunity
      assert [%{status: :no_data}] = ndola.immunity
    end

    test "does nothing to a database that already has cases", %{facilities: facilities} do
      case_fixture(%{facility_id: facilities["UTH"].id})

      assert Demo.seed_activity!() == :skipped
      assert CaseManagement.count_cases() == 1
    end
  end

  describe "reset_activity!/0" do
    setup :seed_reference_data

    setup do
      Demo.ensure_accounts!()
      :seeded = Demo.seed_activity!(DateTime.utc_now() |> DateTime.truncate(:second))
      :ok
    end

    test "clears every kind of demo activity" do
      alert_subscriber_fixture(%{phone: "+260971111111"})

      Demo.reset_activity!()

      refute CaseManagement.any_cases?()
      assert LabReporting.list_lab_tests() == []
      assert LabReporting.list_corrections() == []
      assert DrugAvailability.list_drug_stocks() == []
      assert HospitalCapacity.list_capacity_reports() == []
      assert VaccinationMonitoring.list_vaccination_records() == []
      assert PublicAlerts.list_subscriber_phones() == []
    end

    test "keeps the demo accounts, districts, and facilities" do
      Demo.reset_activity!()

      assert length(Geography.list_districts()) == 3
      assert length(Geography.list_facilities()) == 4

      for %{email: email} <- Demo.accounts() do
        assert Accounts.get_user_by_email_and_password(email, Demo.password())
      end
    end

    test "returns how many rows it deleted from each table" do
      deleted = Demo.reset_activity!()

      assert deleted["cases"] == 24
      assert deleted["lab_tests"] == 4
      assert deleted["lab_result_corrections"] == 1
      assert deleted["lab_correction_acknowledgements"] == 0
      assert deleted["case_outcome_corrections"] == 1
      assert deleted["drug_stocks"] == 8
      assert deleted["capacity_reports"] == 4
      assert deleted["vaccination_records"] == 4
    end

    test "removes alert jobs that are still waiting to run" do
      {:ok, _job} = %{"case_id" => Ecto.UUID.generate()} |> AlertWorker.new() |> Oban.insert()
      assert_enqueued worker: AlertWorker

      assert Demo.reset_activity!()["oban_jobs"] == 1
      refute_enqueued worker: AlertWorker
    end

    test "followed by seed_activity!/1, brings back a correction notice someone already marked as seen" do
      worker = Accounts.get_user_by_email("health.worker@example.com")
      [notice] = LabReporting.list_correction_notices(worker.id)
      {:ok, _ack} = LabReporting.acknowledge_correction(notice.id, worker)
      assert LabReporting.list_correction_notices(worker.id) == []

      Demo.reset_activity!()

      assert Demo.seed_activity!() == :seeded
      assert [_notice] = LabReporting.list_correction_notices(worker.id)
      assert CaseManagement.count_cases() == 23
    end
  end

  describe "reset_on_boot?/0" do
    setup :restore_reset_flag

    test "is off unless configured" do
      Application.delete_env(:zamhealthwatch, :demo_reset_on_boot)
      refute Demo.reset_on_boot?()

      Application.put_env(:zamhealthwatch, :demo_reset_on_boot, false)
      refute Demo.reset_on_boot?()
    end

    test "is on when configured" do
      Application.put_env(:zamhealthwatch, :demo_reset_on_boot, true)
      assert Demo.reset_on_boot?()
    end
  end

  # The flag is global application config, so put back whatever
  # config/runtime.exs set once the test is done. (This module isn't
  # async, so no other test sees the temporary value.)
  defp restore_reset_flag(_context) do
    original = Application.fetch_env(:zamhealthwatch, :demo_reset_on_boot)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:zamhealthwatch, :demo_reset_on_boot, value)
        :error -> Application.delete_env(:zamhealthwatch, :demo_reset_on_boot)
      end
    end)
  end
end
