defmodule ZamHealthWatch.PublicAlerts.ReclassificationAlertWorkerTest do
  # Not async, for the same reason as AlertWorkerTest: the global Logger
  # level is lowered for the span of each test so capture_log sees the
  # worker's info line.
  use ZamHealthWatch.DataCase, async: false
  use Oban.Testing, repo: ZamHealthWatch.Repo

  import ExUnit.CaptureLog
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.PublicAlertsFixtures

  alias ZamHealthWatch.PublicAlerts.ReclassificationAlertWorker

  setup do
    original_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_level) end)

    facility = facility_fixture(%{name: "Kabwata Clinic"})
    case_record = case_fixture(%{disease: :cholera, facility_id: facility.id})
    %{case_record: case_record}
  end

  describe "message/3" do
    test "says a case was ruled out", %{case_record: case_record} do
      message = ReclassificationAlertWorker.message(case_record, "suspected", "not_a_case")

      assert message =~ "Cholera case reported at Kabwata Clinic"
      assert message =~ "has been ruled out by laboratory testing"
    end

    test "corrects an earlier ruled-out notice when the case is confirmed after all", %{
      case_record: case_record
    } do
      message = ReclassificationAlertWorker.message(case_record, "not_a_case", "confirmed")

      assert message =~ "ZamHealthWatch correction"
      assert message =~ "That was wrong - the case is confirmed."
    end

    test "says the case is under investigation again when it's back to suspected", %{
      case_record: case_record
    } do
      message = ReclassificationAlertWorker.message(case_record, "not_a_case", "suspected")

      assert message =~ "the case is under investigation again"
    end
  end

  describe "perform/1" do
    test "notifies every subscriber", %{case_record: case_record} do
      alert_subscriber_fixture(%{phone: "+260971111111"})
      alert_subscriber_fixture(%{phone: "+260972222222"})

      log =
        capture_log(fn ->
          assert :ok =
                   perform_job(ReclassificationAlertWorker, %{
                     "case_id" => case_record.id,
                     "from" => "suspected",
                     "to" => "not_a_case"
                   })
        end)

      assert log =~ "reclassified suspected -> not_a_case - notifying 2 subscriber(s)"
      assert log =~ "+260971111111"
      assert log =~ "+260972222222"
    end
  end
end
