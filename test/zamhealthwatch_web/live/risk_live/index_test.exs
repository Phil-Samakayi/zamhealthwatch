defmodule ZamHealthWatchWeb.RiskLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.HospitalCapacityFixtures

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.HospitalCapacity

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
