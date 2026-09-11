defmodule ZamHealthWatch.PublicAlerts.AlertWorkerTest do
  # Not async: this test temporarily lowers the *global* Logger level
  # (see below) for the span of one capture_log call - narrow, but a real
  # cross-test race under async: true, so this file opts out of it.
  use ZamHealthWatch.DataCase, async: false
  use Oban.Testing, repo: ZamHealthWatch.Repo

  import ExUnit.CaptureLog
  import ZamHealthWatch.CaseManagementFixtures
  import ZamHealthWatch.PublicAlertsFixtures

  alias ZamHealthWatch.PublicAlerts.AlertWorker

  # A tiny, real SmsGateway implementation (not a mocking library - this
  # project doesn't use one anywhere else) that always fails, for the
  # "every delivery failed" retry test below. Defined once here rather
  # than in test/support since nothing else needs it.
  defmodule AlwaysFailingGateway do
    @moduledoc false
    @behaviour ZamHealthWatch.SmsGateway

    @impl true
    def send_sms(_to, _text), do: {:error, :simulated_failure}
  end

  setup do
    # config/test.exs sets the global Logger level to :warning (to keep
    # test output quiet), which drops this worker's Logger.info call
    # before capture_log ever sees it - same fix, same reasoning,
    # AlertWorkerTest already used before this iteration.
    original_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_level) end)
    :ok
  end

  test "notifies every subscriber and logs the outcome" do
    alert_subscriber_fixture(%{phone: "+260971111111"})
    alert_subscriber_fixture(%{phone: "+260972222222"})
    reported_case = case_fixture(%{disease: :cholera})

    log =
      capture_log(fn ->
        assert :ok = perform_job(AlertWorker, %{"case_id" => reported_case.id})
      end)

    assert log =~ "notifying 2 subscriber(s)"
    assert log =~ "cholera"
    assert log =~ reported_case.id
    # SmsGateway.Logger (the default in :test) logs each send too.
    assert log =~ "+260971111111"
    assert log =~ "+260972222222"
  end

  test "still succeeds with no subscribers at all" do
    reported_case = case_fixture()

    log =
      capture_log(fn ->
        assert :ok = perform_job(AlertWorker, %{"case_id" => reported_case.id})
      end)

    assert log =~ "notifying 0 subscriber(s)"
  end

  test "raises (so Oban retries) when the case no longer exists" do
    assert_raise Ecto.NoResultsError, fn ->
      perform_job(AlertWorker, %{"case_id" => Ecto.UUID.generate()})
    end
  end

  test "returns an error (so Oban retries the whole job) when every delivery fails" do
    alert_subscriber_fixture(%{phone: "+260971111111"})
    alert_subscriber_fixture(%{phone: "+260972222222"})
    reported_case = case_fixture()

    original_gateway = Application.get_env(:zamhealthwatch, :sms_gateway)
    Application.put_env(:zamhealthwatch, :sms_gateway, AlwaysFailingGateway)

    on_exit(fn ->
      if original_gateway do
        Application.put_env(:zamhealthwatch, :sms_gateway, original_gateway)
      else
        Application.delete_env(:zamhealthwatch, :sms_gateway)
      end
    end)

    log =
      capture_log(fn ->
        assert {:error, :all_deliveries_failed} =
                 perform_job(AlertWorker, %{"case_id" => reported_case.id})
      end)

    assert log =~ "failed"
  end
end
