defmodule ZamHealthWatchWeb.EpidemiologyLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.CaseManagementFixtures

  alias ZamHealthWatch.CaseManagement

  describe "Epidemiology dashboard" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/epidemiology")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders zeroed stats and an empty facility table with no cases", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/epidemiology")

      assert html =~ "Epidemiology dashboard"
      assert html =~ "Total cases"
      assert html =~ "No cases reported yet."
    end

    test "shows totals broken down by disease, status, and facility", %{conn: conn} do
      facility_a = facility_fixture(%{name: "Clinic A"})
      facility_b = facility_fixture(%{name: "Clinic B"})

      case_fixture(%{disease: :cholera, facility_id: facility_a.id})
      case_fixture(%{disease: :cholera, facility_id: facility_a.id})

      confirmed_case = case_fixture(%{disease: :malaria, facility_id: facility_b.id})
      {:ok, _} = CaseManagement.update_case_status(confirmed_case, %{status: :confirmed})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/epidemiology")

      # Total.
      assert html =~ "<div class=\"stat-value\">3</div>"

      # By-disease tiles.
      assert html =~ "Cholera"
      assert html =~ "Malaria"

      # By-status tiles.
      assert html =~ "Suspected"
      assert html =~ "Confirmed"

      # By-facility table, busiest (Clinic A, 2 cases) listed.
      assert html =~ "Clinic A"
      assert html =~ "Clinic B"
      refute html =~ "No cases reported yet."
    end

    test "updates live when a new case is reported elsewhere", %{conn: conn} do
      facility = facility_fixture(%{name: "Live Clinic"})
      user = user_fixture()

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/epidemiology")

      assert html =~ "<div class=\"stat-value\">0</div>"

      case_fixture(%{disease: :typhoid, facility_id: facility.id, reported_by_id: user.id})
      # The dashboard only reacts to cases created through CaseManagement's
      # broadcasting create_case/1 - case_fixture/1 goes through it, so no
      # manual broadcast is needed here, same as CaseLive.Index's own
      # cross-LiveView broadcast test.

      assert render(lv) =~ "<div class=\"stat-value\">1</div>"
      assert render(lv) =~ "Live Clinic"
    end
  end
end
