defmodule ZamHealthWatch.PublicAlerts.SubscriberTest do
  # Not async: Subscriber is registered under a fixed name (it's a
  # singleton in the running app), so two instances can't be started at
  # the same time - see the moduledoc for why it isn't started
  # automatically in :test at all.
  use ZamHealthWatch.DataCase, async: false
  use Oban.Testing, repo: ZamHealthWatch.Repo

  import ZamHealthWatch.CaseManagementFixtures

  alias ZamHealthWatch.PublicAlerts.AlertWorker
  alias ZamHealthWatch.PublicAlerts.Subscriber

  test "enqueues an alert job when a case is reported" do
    pid = start_supervised!(Subscriber)
    Ecto.Adapters.SQL.Sandbox.allow(ZamHealthWatch.Repo, self(), pid)

    reported_case = case_fixture()

    # Subscriber handles PubSub messages asynchronously - :sys.get_state/1
    # is a synchronous round trip to it, so by the time it returns we know
    # the {:created, case} broadcast above has already been processed.
    _ = :sys.get_state(pid)

    assert_enqueued(worker: AlertWorker, args: %{case_id: reported_case.id})
  end

  test "does not enqueue a second alert job for a status update" do
    pid = start_supervised!(Subscriber)
    Ecto.Adapters.SQL.Sandbox.allow(ZamHealthWatch.Repo, self(), pid)

    reported_case = case_fixture()
    _ = :sys.get_state(pid)

    # Exactly one job so far - the report itself.
    assert [_job] = all_enqueued(worker: AlertWorker, args: %{case_id: reported_case.id})

    {:ok, _updated} =
      ZamHealthWatch.CaseManagement.update_case_status(reported_case, %{status: :confirmed})

    _ = :sys.get_state(pid)

    # Still exactly one - the status update didn't add another.
    assert [_job] = all_enqueued(worker: AlertWorker, args: %{case_id: reported_case.id})
  end
end
