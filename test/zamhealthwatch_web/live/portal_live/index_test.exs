defmodule ZamHealthWatchWeb.PortalLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures
  import ZamHealthWatch.HospitalCapacityFixtures

  describe "Portal" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/portal")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "shows a prompt to get assigned when the user has no facility", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/portal")

      assert html =~ "haven&#39;t been assigned to a facility yet"
      assert html =~ "Manage users"
      refute html =~ "Record capacity"
    end

    test "shows the facility name and an empty state with no activity yet", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      user = user_fixture() |> set_role(:health_worker, facility.id)

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/portal")

      assert html =~ "Kabwata Clinic"
      assert html =~ "No capacity reports yet."
      assert html =~ "No cases reported at this facility yet."
      assert html =~ "No drug stock recorded at this facility yet."
    end

    test "shows recent cases, drug stock, and capacity status scoped to the user's own facility",
         %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture(%{name: "Ndola Teaching Hospital"})
      user = user_fixture() |> set_role(:health_worker, facility.id)

      case_fixture(%{facility_id: facility.id, disease: :cholera})
      _other_case = case_fixture(%{facility_id: other_facility.id, disease: :measles})

      drug_stock_fixture(%{
        facility_id: facility.id,
        medicine: :ors,
        quantity_on_hand: 5,
        reorder_level: 50
      })

      capacity_report_fixture(%{facility_id: facility.id, total_beds: 100, occupied_beds: 90})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/portal")

      assert html =~ "Cholera"
      refute html =~ "Measles"
      assert html =~ "ORS (Oral Rehydration Salts)"
      assert html =~ "Shortage"
      assert html =~ "Near capacity"
    end

    test "only reacts to PubSub events for the viewer's own facility", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture()
      user = user_fixture() |> set_role(:health_worker, facility.id)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/portal")

      # A case at a different facility shouldn't show up here at all.
      case_fixture(%{facility_id: other_facility.id, disease: :measles})
      refute render(lv) =~ "Measles"

      # A case at the viewer's own facility should appear live, no reload.
      case_fixture(%{facility_id: facility.id, disease: :typhoid})
      assert render(lv) =~ "Typhoid"
    end
  end
end
