defmodule ZamHealthWatchWeb.CaseLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.CaseManagementFixtures

  alias ZamHealthWatch.CaseManagement

  describe "Case list" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/cases")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders the report form and an empty state when there are no cases", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/cases")

      assert html =~ "Report a case"
      assert html =~ "Select a disease"
      assert html =~ "No cases reported yet"
    end

    test "lists existing cases", %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      case_fixture(%{disease: :malaria, facility_id: facility.id})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/cases")

      assert html =~ "Test Clinic"
      assert html =~ "Malaria"
      assert html =~ "Suspected"
      refute html =~ "No cases reported yet"
    end
  end

  describe "report case form" do
    setup %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user, facility: facility}
    end

    test "reports a case with valid data", %{conn: conn, user: user, facility: facility} do
      {:ok, lv, _html} = live(conn, ~p"/cases")

      result =
        lv
        |> form("#case-form", %{
          "case" => %{"disease" => "cholera", "facility_id" => facility.id}
        })
        |> render_submit()

      assert result =~ "Case reported."
      assert result =~ "Test Clinic"

      assert [reported_case] = CaseManagement.list_cases()
      assert reported_case.disease == :cholera
      assert reported_case.facility_id == facility.id
      assert reported_case.reported_by_id == user.id
      assert reported_case.status == :suspected
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/cases")

      result =
        lv
        |> element("#case-form")
        |> render_change(%{"case" => %{"disease" => "", "facility_id" => ""}})

      # Phoenix.HTML escapes the apostrophe in Ecto's default message.
      assert result =~ "can&#39;t be blank"
    end

    test "ignores a client-supplied reported_by_id and uses the current user", %{
      conn: conn,
      user: user,
      facility: facility
    } do
      other_user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/cases")

      # `reported_by_id` isn't a field on the rendered form, so there's no
      # real DOM input to drive via `form/3` - the whole point of this test
      # is a tampered/forged param that has no corresponding form field.
      # `render_submit/3` pushes the "save" event straight to the LiveView
      # with an arbitrary payload, the same way a hand-crafted request would.
      render_submit(lv, "save", %{
        "case" => %{
          "disease" => "typhoid",
          "facility_id" => facility.id,
          "reported_by_id" => other_user.id
        }
      })

      assert [reported_case] = CaseManagement.list_cases()
      assert reported_case.reported_by_id == user.id
    end

    test "broadcasts a newly reported case to other viewers live", %{
      conn: conn,
      facility: facility
    } do
      {:ok, lv1, _html} = live(conn, ~p"/cases")
      {:ok, lv2, _html} = live(conn, ~p"/cases")

      lv1
      |> form("#case-form", %{
        "case" => %{"disease" => "measles", "facility_id" => facility.id}
      })
      |> render_submit()

      assert render(lv2) =~ "Measles"
      assert render(lv2) =~ "Test Clinic"
    end
  end
end
