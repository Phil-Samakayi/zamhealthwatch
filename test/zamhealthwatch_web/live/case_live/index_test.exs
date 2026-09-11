defmodule ZamHealthWatchWeb.CaseLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.CaseManagementFixtures

  alias ZamHealthWatch.Accounts
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

    test "shows a web-registered reporter's email", %{conn: conn} do
      reporter = user_fixture()
      case_fixture(%{reported_by_id: reporter.id})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/cases")

      assert html =~ reporter.email
    end

    test "shows an SMS-only reporter's phone number, not an email", %{conn: conn} do
      {:ok, reporter} = Accounts.find_or_create_sms_reporter("+260971234567")
      case_fixture(%{reported_by_id: reporter.id})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/cases")

      assert html =~ "+260971234567"
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

  describe "case status transitions" do
    setup %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      %{conn: conn, facility: facility}
    end

    test "shows no action button for a user with no assigned role", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/cases")

      refute has_element?(lv, row_selector(case) <> " button")
    end

    test "shows a Confirm button for a suspected case when the user has a role", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/cases")

      assert has_element?(lv, row_selector(case) <> " button", "Confirm")
    end

    test "shows a Resolve button for a confirmed case when the user has a role", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})
      {:ok, _} = CaseManagement.update_case_status(case, %{status: :confirmed})
      user = user_fixture() |> set_role(:district_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/cases")

      # Scoped to *this test's own case row* (`row_selector/1`, via the
      # stream's `id="cases-<case-id>"`), not just "any button on the
      # page" - `async: true` means other tests' cases can genuinely be
      # on this page too (see `row_selector/1`'s own doc comment), and a
      # page-wide `has_element?(lv, "button", "Confirm")` would trip on
      # one of theirs exactly the way an unscoped `html =~ "Confirm"`
      # substring check trips on this row's own "Confirmed" badge text.
      assert has_element?(lv, row_selector(case) <> " button", "Resolve")
      refute has_element?(lv, row_selector(case) <> " button", "Confirm")
    end

    test "shows no action button for a resolved case, even with a role assigned", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})
      {:ok, case} = CaseManagement.update_case_status(case, %{status: :confirmed})
      {:ok, case} = CaseManagement.update_case_status(case, %{status: :resolved})
      user = user_fixture() |> set_role(:moh_admin)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/cases")

      refute has_element?(lv, row_selector(case) <> " button")
    end

    test "clicking the action button advances the case status and flashes success", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/cases")

      result = lv |> element(row_selector(case) <> " button", "Confirm") |> render_click()

      assert result =~ "Case moved to Confirmed."

      # The status/button change itself doesn't land in `result` - it comes
      # from the `{:updated, case}` PubSub broadcast `advance_case_status/2`
      # sends, which this same LiveView only picks up via its own
      # `handle_info/2` *after* replying to this click (see the code
      # comment on `handle_event("advance_status", ...)`). Re-rendering
      # picks up whatever that handle_info already delivered to the
      # process's mailbox by the time this call reaches it - the same
      # ordering the "broadcasts a newly reported case to other viewers
      # live" test above relies on with a second `render/1` call.
      assert has_element?(lv, row_selector(case) <> " button", "Resolve")
      assert CaseManagement.get_case!(case.id).status == :confirmed
    end

    test "a forged advance_status event is rejected server-side for a user with no role", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/cases")

      # No button is rendered for a roleless user (see the test above), so
      # this pushes the event directly - a forged request has no button to
      # click either, same technique the "ignores a client-supplied
      # reported_by_id" test above uses for the "save" event.
      result = render_click(lv, "advance_status", %{"id" => case.id})

      assert result =~ "You need an assigned role to change a case&#39;s status."
      assert CaseManagement.get_case!(case.id).status == :suspected
    end

    test "a forged advance_status event on an already-resolved case is rejected", %{
      conn: conn,
      facility: facility
    } do
      case = case_fixture(%{facility_id: facility.id})
      {:ok, case} = CaseManagement.update_case_status(case, %{status: :confirmed})
      {:ok, case} = CaseManagement.update_case_status(case, %{status: :resolved})
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/cases")

      result = render_click(lv, "advance_status", %{"id" => case.id})

      assert result =~ "This case has no further status to move to."
      assert CaseManagement.get_case!(case.id).status == :resolved
    end

    # Scopes an assertion to one case's own table row. `async: true` means
    # other tests' cases can genuinely show up on *this* page too - every
    # test mounts its own LiveView subscribed to the same global "cases"
    # PubSub topic, and a `{:created, _}`/`{:updated, _}` broadcast from a
    # concurrently-running test's case (a wholly different Ecto Sandbox
    # transaction) still lands on this LiveView's `handle_info/2` and gets
    # streamed in here too - PubSub has no notion of per-test DB isolation
    # the way `Repo` queries do. A page-wide `has_element?(lv, "button",
    # ...)` can't tell "this test's row" from "some other test's row";
    # scoping to the specific stream row's DOM id (Phoenix's default
    # `stream/3` id, `"<name>-<item-id>"`, confirmed against this project's
    # own rendered HTML) can.
    defp row_selector(%{id: id}), do: "#cases-#{id}"
  end
end
