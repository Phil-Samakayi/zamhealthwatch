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

  describe "facility scoping for health workers" do
    test "an unassigned health_worker sees a get-assigned message instead of the form", %{
      conn: conn
    } do
      user = user_fixture() |> set_role(:health_worker)

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      assert html =~ "haven&#39;t been assigned to a facility yet"
      assert html =~ "Manage users"
      refute html =~ "id=\"lab-test-form\""
    end

    test "an assigned health_worker only sees lab tests for cases at their own facility", %{
      conn: conn
    } do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture(%{name: "Ndola Teaching Hospital"})
      user = user_fixture() |> set_role(:health_worker, facility.id)

      own_case = case_fixture(%{facility_id: facility.id, disease: :cholera})
      other_case = case_fixture(%{facility_id: other_facility.id, disease: :measles})
      lab_test_fixture(%{case_id: own_case.id})
      lab_test_fixture(%{case_id: other_case.id})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      assert html =~ "Cholera"
      refute html =~ "Measles"
    end

    test "the case dropdown only offers cases at the health_worker's own facility", %{
      conn: conn
    } do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture(%{name: "Ndola Teaching Hospital"})
      user = user_fixture() |> set_role(:health_worker, facility.id)

      case_fixture(%{facility_id: facility.id, disease: :cholera})
      case_fixture(%{facility_id: other_facility.id, disease: :measles})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      assert html =~ "Cholera"
      refute html =~ "Ndola Teaching Hospital"
    end

    test "a forged case_id for another facility's case is rejected server-side", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture()
      user = user_fixture() |> set_role(:health_worker, facility.id)
      other_case = case_fixture(%{facility_id: other_facility.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/labs")

      result = render_submit(lv, "save", %{"lab_test" => %{"case_id" => other_case.id}})

      assert result =~ "You can only request tests for cases at your own facility."
      assert LabReporting.list_lab_tests() == []
    end
  end

  describe "recording a result" do
    setup %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      case_record = case_fixture(%{disease: :cholera, facility_id: facility.id})
      lab_officer = user_fixture() |> set_role(:lab_officer)
      %{conn: conn, case_record: case_record, lab_officer: lab_officer}
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

    test "shows Positive/Negative/Inconclusive buttons for a pending test to a lab officer",
         %{conn: conn, case_record: case_record, lab_officer: lab_officer} do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      assert has_element?(lv, row_selector(lab_test) <> " button", "Positive")
      assert has_element?(lv, row_selector(lab_test) <> " button", "Negative")
      assert has_element?(lv, row_selector(lab_test) <> " button", "Inconclusive")
    end

    test "shows no result buttons to roles other than lab officer", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      for role <- [:district_officer, :moh_admin] do
        {:ok, lv, _html} =
          conn
          |> log_in_user(user_fixture() |> set_role(role))
          |> live(~p"/labs")

        refute has_element?(lv, row_selector(lab_test) <> " button")
      end
    end

    test "offers Correct/Withdraw instead of result buttons once a test is resulted", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      refute has_element?(lv, row_selector(lab_test) <> " button", "Positive")
      assert has_element?(lv, row_selector(lab_test) <> " button", "Correct")
      assert has_element?(lv, row_selector(lab_test) <> " button", "Withdraw")
    end

    test "shows who entered a result", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture() |> set_role(:district_officer))
        |> live(~p"/labs")

      assert has_element?(lv, row_selector(lab_test), lab_officer.email)
    end

    test "clicking Positive records the result and confirms the linked case", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      result =
        lv
        |> element(row_selector(lab_test) <> " button", "Positive")
        |> render_click()

      assert result =~ "Result recorded: Positive."
      assert has_element?(lv, row_selector(lab_test), "Positive")
      assert LabReporting.get_lab_test!(lab_test.id).status == :resulted
      assert LabReporting.get_lab_test!(lab_test.id).resulted_by_id == lab_officer.id
      assert CaseManagement.get_case!(case_record.id).status == :confirmed
    end

    test "clicking Negative records the result and rules the linked case out", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      lv
      |> element(row_selector(lab_test) <> " button", "Negative")
      |> render_click()

      assert CaseManagement.get_case!(case_record.id).status == :not_a_case
    end

    test "clicking Inconclusive records the result and leaves the case status unchanged", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      lv
      |> element(row_selector(lab_test) <> " button", "Inconclusive")
      |> render_click()

      assert CaseManagement.get_case!(case_record.id).status == :suspected
    end

    test "a forged record_result event is rejected server-side for a non-lab role", %{
      conn: conn,
      case_record: case_record
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture() |> set_role(:district_officer))
        |> live(~p"/labs")

      result = render_click(lv, "record_result", %{"id" => lab_test.id, "result" => "positive"})

      assert result =~ "Only a lab officer can record a lab result."
      assert LabReporting.get_lab_test!(lab_test.id).status == :pending
    end

    test "a forged record_result event on an already-resulted test is rejected", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      result = render_click(lv, "record_result", %{"id" => resulted.id, "result" => "negative"})

      assert result =~ "This test already has a recorded result."
      assert LabReporting.get_lab_test!(lab_test.id).result == :positive
    end

    test "a forged record_result event with an unrecognized result value is rejected gracefully",
         %{conn: conn, case_record: case_record, lab_officer: lab_officer} do
      lab_test = lab_test_fixture(%{case_id: case_record.id})

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      result = render_click(lv, "record_result", %{"id" => lab_test.id, "result" => "hacked"})

      assert result =~ "Unrecognized result value."
      assert LabReporting.get_lab_test!(lab_test.id).status == :pending
    end

    test "a lab officer corrects a result through the panel, and the history shows it", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      lv |> element(row_selector(lab_test) <> " button", "Correct") |> render_click()
      assert has_element?(lv, "#correction-panel", "Correct a result")

      result =
        lv
        |> form("#correction-form", %{
          "correction" => %{
            "new_result" => "negative",
            "reason" => "Repeat test on a fresh sample was negative."
          }
        })
        |> render_submit()

      assert result =~ "Result corrected to Negative."
      refute has_element?(lv, "#correction-panel")
      assert LabReporting.get_lab_test!(lab_test.id).status == :corrected
      assert CaseManagement.get_case!(case_record.id).status == :not_a_case

      assert has_element?(lv, "#correction-history", "Positive → Negative")
      assert has_element?(lv, "#correction-history", "Repeat test on a fresh sample was negative.")
    end

    test "a too-short reason is shown as an error and nothing changes", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      lv |> element(row_selector(lab_test) <> " button", "Correct") |> render_click()

      result =
        lv
        |> form("#correction-form", %{
          "correction" => %{"new_result" => "negative", "reason" => "oops"}
        })
        |> render_submit()

      assert result =~ "should be at least 10 character(s)"
      assert has_element?(lv, "#correction-panel")
      assert LabReporting.get_lab_test!(lab_test.id).result == :positive
    end

    test "a lab officer withdraws a result through the panel", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(lab_officer)
        |> live(~p"/labs")

      lv |> element(row_selector(lab_test) <> " button", "Withdraw") |> render_click()

      result =
        lv
        |> form("#correction-form", %{
          "correction" => %{"reason" => "Entered against the wrong case."}
        })
        |> render_submit()

      assert result =~ "Result withdrawn."
      assert LabReporting.get_lab_test!(lab_test.id).status == :entered_in_error
      assert CaseManagement.get_case!(case_record.id).status == :suspected
      assert has_element?(lv, row_selector(lab_test), "Withdrawn")
      assert has_element?(lv, "#correction-history", "withdrawn (entered in error)")
    end

    test "an MOH admin sees Correct/Withdraw on a resulted test", %{
      conn: conn,
      case_record: case_record,
      lab_officer: lab_officer
    } do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture() |> set_role(:moh_admin))
        |> live(~p"/labs")

      assert has_element?(lv, row_selector(lab_test) <> " button", "Correct")
    end

    test "a district officer gets no Correct button, and forged correction events are refused",
         %{conn: conn, case_record: case_record, lab_officer: lab_officer} do
      lab_test = lab_test_fixture(%{case_id: case_record.id})
      {:ok, _resulted} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture() |> set_role(:district_officer))
        |> live(~p"/labs")

      refute has_element?(lv, row_selector(lab_test) <> " button", "Correct")

      result = render_click(lv, "start_correction", %{"id" => lab_test.id, "mode" => "correct"})
      assert result =~ "Only a lab officer or MOH admin can correct or withdraw a result."
      refute has_element?(lv, "#correction-panel")

      result =
        render_submit(lv, "submit_correction", %{
          "correction" => %{
            "lab_test_id" => lab_test.id,
            "mode" => "correct",
            "new_result" => "negative",
            "reason" => "A forged but long enough reason."
          }
        })

      assert result =~ "Only a lab officer or MOH admin can correct or withdraw a result."
      assert LabReporting.get_lab_test!(lab_test.id).result == :positive
    end

    # Same PubSub-leakage risk CaseLive.IndexTest's own row_selector/1
    # already documents - every test here mounts its own LiveView
    # subscribed to the same global "lab_tests" topic, so a concurrently
    # running test's `{:created, _}`/`{:updated, _}` broadcast can land
    # on this one too. Scoped to this test's own stream row (Phoenix's
    # default `stream/3` id) rather than a page-wide element check.
    defp row_selector(%{id: id}), do: "#lab_tests-#{id}"
  end

  describe "correction notices for the requester" do
    setup %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      case_record = case_fixture(%{disease: :cholera, facility_id: facility.id})
      requester = user_fixture() |> set_role(:health_worker, facility.id)
      lab_officer = user_fixture() |> set_role(:lab_officer)

      lab_test = lab_test_fixture(%{case_id: case_record.id, requested_by_id: requester.id})
      {:ok, issued} = LabReporting.record_result(lab_test, :positive, lab_officer)

      {:ok, _} =
        LabReporting.correct_result(issued, :negative, "Repeat test negative.", lab_officer)

      %{conn: conn, requester: requester, lab_test: lab_test}
    end

    test "the requester sees the correction and can mark it as seen", %{
      conn: conn,
      requester: requester
    } do
      {:ok, lv, _html} =
        conn
        |> log_in_user(requester)
        |> live(~p"/labs")

      assert has_element?(lv, "#correction-notices", "Positive → Negative")
      assert has_element?(lv, "#correction-notices", "Repeat test negative.")

      lv |> element("#correction-notices button", "Mark as seen") |> render_click()

      refute has_element?(lv, "#correction-notices")
      assert LabReporting.list_correction_notices(requester.id) == []
    end

    test "other users don't see the requester's notice", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture() |> set_role(:district_officer))
        |> live(~p"/labs")

      refute has_element?(lv, "#correction-notices")
    end

    test "a forged acknowledgement from someone else is refused", %{
      conn: conn,
      requester: requester
    } do
      [notice] = LabReporting.list_correction_notices(requester.id)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture() |> set_role(:district_officer))
        |> live(~p"/labs")

      result = render_click(lv, "acknowledge_correction", %{"id" => notice.id})

      assert result =~ "Only the person who requested this test can mark it as seen."
      assert [_still_there] = LabReporting.list_correction_notices(requester.id)
    end
  end
end
