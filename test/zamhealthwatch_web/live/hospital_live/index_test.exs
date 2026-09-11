defmodule ZamHealthWatchWeb.HospitalLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures

  alias ZamHealthWatch.HospitalCapacity

  describe "Capacity report list" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/hospitals")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders the form and an empty state when there are no reports", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/hospitals")

      assert html =~ "Record hospital capacity"
      assert html =~ "Select a facility"
      assert html =~ "No capacity reports recorded yet."
    end

    test "lists existing reports", %{conn: conn} do
      facility = facility_fixture(%{name: "Ndola Teaching Hospital"})

      capacity_report_fixture(%{
        facility_id: facility.id,
        total_beds: 100,
        occupied_beds: 40,
        admissions_today: 7
      })

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/hospitals")

      assert html =~ "Ndola Teaching Hospital"
      assert html =~ "40/100"
      refute html =~ "No capacity reports recorded yet."
    end
  end

  describe "record capacity form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "records capacity with valid data", %{conn: conn, user: user} do
      facility = facility_fixture()
      {:ok, lv, _html} = live(conn, ~p"/hospitals")

      result =
        lv
        |> form("#capacity-form", %{
          "capacity_report" => %{
            "facility_id" => facility.id,
            "total_beds" => "100",
            "occupied_beds" => "60",
            "icu_beds_total" => "10",
            "icu_beds_occupied" => "5",
            "admissions_today" => "12"
          }
        })
        |> render_submit()

      assert result =~ "Capacity report recorded."

      assert [report] = HospitalCapacity.list_capacity_reports()
      assert report.facility_id == facility.id
      assert report.total_beds == 100
      assert report.reported_by_id == user.id
    end

    test "renders errors with invalid data (no facility selected)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/hospitals")

      result =
        lv
        |> form("#capacity-form", %{
          "capacity_report" => %{
            "facility_id" => "",
            "total_beds" => "100",
            "occupied_beds" => "60",
            "icu_beds_total" => "10",
            "icu_beds_occupied" => "5",
            "admissions_today" => "12"
          }
        })
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "ignores a client-supplied reported_by_id and uses the current user", %{
      conn: conn,
      user: user
    } do
      facility = facility_fixture()
      other_user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/hospitals")

      render_submit(lv, "save", %{
        "capacity_report" => %{
          "facility_id" => facility.id,
          "total_beds" => "100",
          "occupied_beds" => "60",
          "icu_beds_total" => "10",
          "icu_beds_occupied" => "5",
          "admissions_today" => "12",
          "reported_by_id" => other_user.id
        }
      })

      assert [report] = HospitalCapacity.list_capacity_reports()
      assert report.reported_by_id == user.id
    end

    test "broadcasts a newly recorded capacity report to other viewers live", %{conn: conn} do
      facility = facility_fixture(%{name: "Monze Mission Hospital"})

      {:ok, lv1, _html} = live(conn, ~p"/hospitals")
      {:ok, lv2, _html} = live(conn, ~p"/hospitals")

      lv1
      |> form("#capacity-form", %{
        "capacity_report" => %{
          "facility_id" => facility.id,
          "total_beds" => "100",
          "occupied_beds" => "60",
          "icu_beds_total" => "10",
          "icu_beds_occupied" => "5",
          "admissions_today" => "12"
        }
      })
      |> render_submit()

      assert render(lv2) =~ "Monze Mission Hospital"
    end
  end

  describe "capacity status badge" do
    test "shows an adequate badge below 80% bed occupancy", %{conn: conn} do
      facility = facility_fixture()
      capacity_report_fixture(%{facility_id: facility.id, occupied_beds: 50, total_beds: 100})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/hospitals")

      assert has_element?(lv, "span.badge-success", "50.0% - Adequate")
    end

    test "shows a near-capacity badge between 80% and 99% bed occupancy", %{conn: conn} do
      facility = facility_fixture()
      capacity_report_fixture(%{facility_id: facility.id, occupied_beds: 85, total_beds: 100})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/hospitals")

      assert has_element?(lv, "span.badge-warning", "85.0% - Near capacity")
    end

    test "shows an over-capacity badge at or above 100% bed occupancy", %{conn: conn} do
      facility = facility_fixture()
      capacity_report_fixture(%{facility_id: facility.id, occupied_beds: 110, total_beds: 100})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/hospitals")

      assert has_element?(lv, "span.badge-error", "110.0% - Over capacity")
    end

    test "shows 'No ICU beds' for a facility with zero ICU beds", %{conn: conn} do
      facility = facility_fixture()

      capacity_report_fixture(%{
        facility_id: facility.id,
        icu_beds_total: 0,
        icu_beds_occupied: 0
      })

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/hospitals")

      assert html =~ "No ICU beds"
    end
  end
end
