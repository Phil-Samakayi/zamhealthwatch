defmodule ZamHealthWatchWeb.NationalReportingLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.VaccinationMonitoringFixtures

  describe "access control" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/reports/national")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects to \"/\" for a logged-in user with no role", %{conn: conn} do
      assert {:error, redirect} =
               conn
               |> log_in_user(user_fixture())
               |> live(~p"/reports/national")

      assert {:redirect, %{to: "/", flash: flash}} = redirect
      assert %{"error" => "You don't have permission to access this page."} = flash
    end

    test "redirects to \"/\" for a logged-in user with a non-admin role", %{conn: conn} do
      user = user_fixture() |> set_role(:health_worker)

      assert {:error, redirect} =
               conn
               |> log_in_user(user)
               |> live(~p"/reports/national")

      assert {:redirect, %{to: "/", flash: flash}} = redirect
      assert %{"error" => "You don't have permission to access this page."} = flash
    end
  end

  describe "national rollup" do
    setup %{conn: conn} do
      admin = user_fixture() |> set_role(:moh_admin)
      %{conn: log_in_user(conn, admin)}
    end

    test "shows an empty state when there are no facilities or vaccination records", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/reports/national")

      assert html =~ "No facilities to report on yet."
      assert html =~ "No vaccination coverage recorded yet."
    end

    test "renders a facility's rolled-up case, lab, and drug stock counts", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      case_fixture(%{facility_id: facility.id, disease: :cholera})
      drug_stock_fixture(%{facility_id: facility.id, quantity_on_hand: 10, reorder_level: 50})

      {:ok, _lv, html} = live(conn, ~p"/reports/national")

      assert html =~ "Kabwata Clinic"
      assert html =~ "1 suspected"
      assert html =~ "1 record, 1 shortage"
    end

    test "renders vaccination coverage by district", %{conn: conn} do
      district = district_fixture(%{name: "Ndola"})
      vaccination_record_fixture(%{district_id: district.id, antigen: :bcg})

      {:ok, _lv, html} = live(conn, ~p"/reports/national")

      assert html =~ "Ndola"
      assert html =~ "BCG"
    end

    test "links to the CSV download", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/reports/national")

      assert has_element?(lv, ~s(a[href="#{~p"/reports/national.csv"}"]), "Download CSV")
    end

    test "recomputes the rollup when a new case comes in", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      {:ok, lv, _html} = live(conn, ~p"/reports/national")

      case_fixture(%{facility_id: facility.id, disease: :cholera})

      assert render(lv) =~ "1 suspected"
    end
  end
end
