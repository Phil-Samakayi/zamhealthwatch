defmodule ZamHealthWatchWeb.LabLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.LabReportingFixtures

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.LabReporting

  describe "Lab test list" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/labs")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders the request form and an empty state when there are no lab tests", %{
      conn: conn
    } do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/labs")

      assert html =~ "Request a lab test"
      assert html =~ "Select a case"
      assert html =~ "No lab tests requested yet."
    end

    test "lists existing lab tests", %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      case_record = case_fixture(%{disease: :cholera, facility_id: facility.id})
      lab_test_fixture(%{case_id: case_record.id})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/labs")

      assert html =~ "Cholera"
      assert html =~ "Test Clinic"
      assert html =~ "Pending"
      refute html =~ "No lab tests requested yet."
    end
  end

  describe "request lab test form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "requests a test with valid data", %{conn: conn, user: user} do
      case_record = case_fixture()
      {:ok, lv, _html} = live(conn, ~p"/labs")

      result =
        lv
        |> form("#lab-test-form", %{"lab_test" => %{"case_id" => case_record.id}})
        |> render_submit()

      assert result =~ "Lab test requested."

      assert [lab_test] = LabReporting.list_lab_tests()
      assert lab_test.case_id == case_record.id
      assert lab_test.requested_by_id == user.id
      assert lab_test.status == :pending
    end

    test "renders errors with invalid data (no case selected)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/labs")

      result =
        lv
        |> form("#lab-test-form", %{"lab_test" => %{"case_id" => ""}})
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "ignores a client-supplied requested_by_id and uses the current user", %{
      conn: conn,
      user: user
    } do
      case_record = case_fixture()
      other_user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/labs")

      render_submit(lv, "save", %{
        "lab_test" => %{"case_id" => case_record.id, "requested_by_id" => other_user.id}
      })

      assert [lab_test] = LabReporting.list_lab_tests()
      assert lab_test.requested_by_id == user.id
    end

    test "broadcasts a newly requested lab test to other viewers live", %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      case_record = case_fixture(%{disease: :cholera, facility_id: facility.id})

      {:ok, lv1, _html} = live(conn, ~p"/labs")
      {:ok, lv2, _html} = live(conn, ~p"/labs")

      lv1
      |> form("#lab-test-form", %{"lab_test" => %{"case_id" => case_record.id}})
      |> render_submit()

      assert render(lv2) =~ "Cholera"
      assert render(lv2) =~ "Test Clinic"
    end
  end

  describe "recording a result" do
    setup %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      case_record = case_fixture(%{disease: :cholera, facility_id: facility.id})
      %{conn: conn, case_record: case_record}
    end

    test "shows no action buttons for a user with no assigned role", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/labs")

      refute has_element?(lv, row_selector(lab_test) <> " button")
    end

    test "shows Positive/Negative/Inconclusive buttons for a pending test when the user has a role",
         %{conn: conn, case_record: case_record} do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      assert has_element?(lv, row_selector(lab_test) <> " button", "Positive")
      assert has_element?(lv, row_selector(lab_test) <> " button", "Negative")
      assert has_element?(lv, row_selector(lab_test) <> " button", "Inconclusive")
    end

    test "shows no action buttons for an already-resulted test, even with a role assigned", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, :health_worker)
      user = user_fixture() |> set_role(:moh_admin)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      refute has_element?(lv, row_selector(lab_test) <> " button")
    end

    test "clicking Positive records the result and confirms the linked case", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      result =
        lv
        |> element(row_selector(lab_test) <> " button", "Positive")
        |> render_click()

      assert result =~ "Result recorded: Positive."
      assert has_element?(lv, row_selector(lab_test), "Positive")
      assert LabReporting.get_lab_test!(lab_test.id).status == :resulted
      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "clicking Negative records the result and resolves the linked case", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      user = user_fixture() |> set_role(:district_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      lv
      |> element(row_selector(lab_test) <> " button", "Negative")
      |> render_click()

      assert CaseManagement.get_case!(case_record.id).status == :resolved
    end

    test "clicking Inconclusive records the result and leaves the case status unchanged", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      user = user_fixture() |> set_role(:moh_admin)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      lv
      |> element(row_selector(lab_test) <> " button", "Inconclusive")
      |> render_click()

      assert CaseManagement.get_case!(case_record.id).status == :suspected
    end

    test "a forged record_result event is rejected server-side for a user with no role", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/labs")

      result = render_click(lv, "record_result", %{"id" => lab_test.id, "result" => "positive"})

      assert result =~ "You need an assigned role to record a lab result."
      assert LabReporting.get_lab_test!(lab_test.id).status == :pending
    end

    test "a forged record_result event on an already-resulted test is rejected", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, resulted} = LabReporting.record_result(lab_test, :positive, :health_worker)
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      result = render_click(lv, "record_result", %{"id" => resulted.id, "result" => "negative"})

      assert result =~ "This test already has a recorded result."
      assert LabReporting.get_lab_test!(lab_test.id).result == :positive
    end

    test "a forged record_result event with an unrecognized result value is rejected gracefully",
         %{conn: conn, case_record: case_record} do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      user = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      result = render_click(lv, "record_result", %{"id" => lab_test.id, "result" => "hacked"})

      assert result =~ "Unrecognized result value."
      assert LabReporting.get_lab_test!(lab_test.id).status == :pending
    end

    # Same PubSub-leakage risk CaseLive.IndexTest's own row_selector/1
    # already documents - every test here mounts its own LiveView
    # subscribed to the same global "lab_tests" topic, so a concurrently
    # running test's `{:created, _}`/`{:updated, _}` broadcast can land
    # on this one too. Scoped to this test's own stream row (Phoenix's
    # default `stream/3` id) rather than a page-wide element check.
    defp row_selector(%{id: id}), do: "#lab_tests-#{id}"
  end
end
