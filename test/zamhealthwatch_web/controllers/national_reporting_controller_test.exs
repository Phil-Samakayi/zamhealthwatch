defmodule ZamHealthWatchWeb.NationalReportingControllerTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.GeographyFixtures

  describe "GET /reports/national.csv" do
    test "redirects to log in when no user is logged in", %{conn: conn} do
      conn = get(conn, ~p"/reports/national.csv")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You must log in to access this page."
    end

    test "redirects home for a logged-in user with no role assigned", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/reports/national.csv")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You don't have permission to access this page."
    end

    test "redirects home for a health_worker", %{conn: conn} do
      user = user_fixture() |> set_role(:health_worker)
      conn = conn |> log_in_user(user) |> get(~p"/reports/national.csv")

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects home for a district_officer", %{conn: conn} do
      user = user_fixture() |> set_role(:district_officer)
      conn = conn |> log_in_user(user) |> get(~p"/reports/national.csv")

      assert redirected_to(conn) == ~p"/"
    end

    test "streams the current snapshot as a CSV download for a moh_admin", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      case_fixture(%{facility_id: facility.id, disease: :cholera})

      user = user_fixture() |> set_role(:moh_admin)
      conn = conn |> log_in_user(user) |> get(~p"/reports/national.csv")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "zamhealthwatch-national-report-"

      assert conn.resp_body =~ "Facility,District,Cases (suspected)"
      assert conn.resp_body =~ "Kabwata Clinic"
    end
  end
end
