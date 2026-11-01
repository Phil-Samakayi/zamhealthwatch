defmodule ZamHealthWatchWeb.RiskLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures
  import ZamHealthWatch.VaccinationMonitoringFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.DrugAvailability

  describe "Outbreak risk" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/risk")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders an insufficient_data row for a facility with no cases", %{conn: conn} do
      facility_fixture(%{name: "Quiet Clinic"})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/risk")

      assert html =~ "Outbreak risk"
      assert html =~ "Quiet Clinic"
      assert html =~ "No data"
      assert html =~ "No reports yet"
      refute html =~ "No facilities to assess yet."
    end

    test "renders a facility's hospital capacity status alongside its risk tier", %{conn: conn} do
      facility = facility_fixture(%{name: "Near Capacity Clinic"})
      capacity_report_fixture(%{facility_id: facility.id, total_beds: 100, occupied_beds: 90})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/risk")

      assert html =~ "Near Capacity Clinic"
      assert html =~ "Near capacity"
      refute html =~ "No reports yet"
    end

    test "renders the empty state with no facilities at all", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/risk")

      assert html =~ "No facilities to assess yet."
      assert html =~ "No districts to assess yet."
    end

    test "renders a district's risk with a trend for each disease", %{conn: conn} do
      district = district_fixture(%{name: "Chongwe", province: "Lusaka"})
      facility = facility_fixture(%{name: "Chongwe Clinic", district_id: district.id})
      user = user_fixture()

      for disease <- [:cholera, :cholera, :malaria] do
        {:ok, _case} =
          CaseManagement.create_case(%{
            disease: disease,
            facility_id: facility.id,
            reported_by_id: user.id
          })
      end

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      row = lv |> element("#district-#{district.id}") |> render()
      assert row =~ "Chongwe"
      assert row =~ "(Lusaka)"
      assert row =~ "Cholera"
      assert row =~ "0 → 0 → 0 → 2"
      assert row =~ "Malaria"
      assert row =~ "0 → 0 → 0 → 1"
    end

    test "shows a district with no recent cases as having no data", %{conn: conn} do
      district = district_fixture(%{name: "Quiet District"})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/risk")

      row = lv |> element("#district-#{district.id}") |> render()
      assert row =~ "No data"
      assert row =~ "No cases in the last 4 weeks"
      assert row =~ "No coverage data"
    end

    test "raises measles to High where coverage leaves an immunity gap, and says why", %{
      conn: conn
    } do
      district = district_fixture(%{name: "Monze"})
      facility = facility_fixture(%{district_id: district.id})
      user = user_fixture()

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :measles,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      vaccination_record_fixture(%{
        district_id: district.id,
        antigen: :measles_rubella,
        doses_administered: 1900,
        target_population: 4000
      })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      assert has_element?(lv, "#district-#{district.id} span.badge-error", "High")
      assert has_element?(lv, "#district-#{district.id} span.badge-warning", "47.5% - gap")

      assert lv |> element("#district-#{district.id}") |> render() =~
               "Cases with Measles-Rubella coverage at 47.5%"
    end

    test "lists a supply alert for a shortage where the medicine is needed", %{conn: conn} do
      facility = facility_fixture(%{name: "Alert Clinic"})
      user = user_fixture()

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :cholera,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      drug_stock_fixture(%{
        facility_id: facility.id,
        medicine: :ors,
        quantity_on_hand: 40,
        reorder_level: 100
      })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      row = lv |> element("#supply-alert-#{facility.id}-ors") |> render()
      assert row =~ "Alert Clinic"
      assert row =~ "ORS (Oral Rehydration Salts)"
      assert row =~ "40 / 100"
      assert row =~ "Cholera"
      refute has_element?(lv, "#no-supply-alerts")
    end

    test "adds a supply alert live when a shortage is reported", %{conn: conn} do
      facility = facility_fixture()
      user = user_fixture()

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :malaria,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      refute has_element?(lv, "#supply-alert-#{facility.id}-al")

      {:ok, _stock} =
        DrugAvailability.record_stock(%{
          medicine: :al,
          quantity_on_hand: 10,
          reorder_level: 60,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      assert has_element?(lv, "#supply-alert-#{facility.id}-al", "10 / 60")
    end

    test "updates a district live when vaccination coverage is reported", %{conn: conn} do
      district = district_fixture(%{name: "Coverage District"})
      facility = facility_fixture(%{district_id: district.id})
      user = user_fixture()

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :measles,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      assert has_element?(lv, "#district-#{district.id} span.badge-ghost", "No coverage data")
      refute has_element?(lv, "#district-#{district.id} span.badge-error", "High")

      {:ok, _record} =
        VaccinationMonitoring.record_vaccination(%{
          antigen: :measles_rubella,
          campaign: "Routine - 2026",
          doses_administered: 70,
          target_population: 100,
          district_id: district.id,
          reported_by_id: user.id
        })

      assert has_element?(lv, "#district-#{district.id} span.badge-error", "High")
      assert has_element?(lv, "#district-#{district.id} span.badge-warning", "70.0% - gap")
    end

    test "updates a district live when a case is reported at one of its facilities", %{
      conn: conn
    } do
      district = district_fixture(%{name: "Live District"})
      facility = facility_fixture(%{district_id: district.id})
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      assert lv |> element("#district-#{district.id}") |> render() =~
               "No cases in the last 4 weeks"

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :typhoid,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      row = lv |> element("#district-#{district.id}") |> render()
      assert row =~ "Typhoid"
      refute row =~ "No cases in the last 4 weeks"
    end

    test "updates live when a new case is reported elsewhere", %{conn: conn} do
      facility = facility_fixture(%{name: "Live Clinic"})
      user = user_fixture()

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      assert html =~ "No data"

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :typhoid,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      # The view only reacts to cases created through CaseManagement's
      # broadcasting create_case/1, same as EpidemiologyLive.Index and
      # MapLive.Index's own live-update tests - no manual broadcast
      # needed here.
      assert render(lv) =~ "Live Clinic"
      refute render(lv) =~ "No data"
    end

    test "updates live when a new capacity report is submitted elsewhere", %{conn: conn} do
      facility = facility_fixture(%{name: "Capacity Clinic"})
      user = user_fixture()

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/risk")

      assert html =~ "No reports yet"

      {:ok, _report} =
        HospitalCapacity.record_capacity(%{
          total_beds: 100,
          occupied_beds: 95,
          icu_beds_total: 10,
          icu_beds_occupied: 8,
          admissions_today: 5,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      # The view only reacts to capacity reports created through
      # HospitalCapacity's broadcasting record_capacity/1, same as the
      # case live-update test above - no manual broadcast needed here.
      assert render(lv) =~ "Near capacity"
      refute render(lv) =~ "No reports yet"
    end
  end
end
