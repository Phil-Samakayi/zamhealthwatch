defmodule ZamHealthWatch.PublicAlerts.AlertWorkerTest do
  # Not async: this test temporarily lowers the *global* Logger level
  # (see below) for the span of one capture_log call - narrow, but a real
  # cross-test race under async: true, so this file opts out of it.
  use ZamHealthWatch.DataCase, async: false
  use Oban.Testing, repo: ZamHealthWatch.Repo

  import ExUnit.CaptureLog
  import ZamHealthWatch.CaseManagementFixtures

  alias ZamHealthWatch.PublicAlerts.AlertWorker

  test "logs a mock alert for the given case" do
    reported_case = case_fixture(%{disease: :cholera})

    # config/test.exs sets the global Logger level to :warning (to keep
    # test output quiet), which drops the worker's Logger.info call
    # before capture_log ever sees it. Neither capture_log's own :level
    # option (relaxes only its capturing handler, not the primary filter
    # that already dropped the event) nor Logger.put_process_level/2
    # (tried first - didn't take, most likely because perform_job/3
    # doesn't run the worker in this exact test process) got past that.
    # Reconfiguring the level directly is unambiguous regardless of which
    # process actually logs; on_exit guarantees it's restored even if an
    # assertion below fails.
    original_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_level) end)

    log =
      capture_log(fn ->
        assert :ok = perform_job(AlertWorker, %{"case_id" => reported_case.id})
      end)

    assert log =~ "PUBLIC ALERT (mock delivery)"
    assert log =~ "cholera"
    assert log =~ reported_case.id
  end

  test "raises (so Oban retries) when the case no longer exists" do
    assert_raise Ecto.NoResultsError, fn ->
      perform_job(AlertWorker, %{"case_id" => Ecto.UUID.generate()})
    end
  end
end
