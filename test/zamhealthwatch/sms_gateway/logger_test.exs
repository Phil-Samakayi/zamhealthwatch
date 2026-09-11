defmodule ZamHealthWatch.SmsGateway.LoggerTest do
  # Temporarily raises the *global* Logger level to capture output under
  # this project's :warning test log level - same trade-off (and same
  # reason) AlertWorkerTest already opts out of async for.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZamHealthWatch.SmsGateway.Logger, as: SmsLogger

  test "logs the recipient and text, and returns :ok" do
    original_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_level) end)

    log =
      capture_log(fn ->
        assert :ok = SmsLogger.send_sms("+260971234567", "hello there")
      end)

    assert log =~ "SMS (mock delivery)"
    assert log =~ "+260971234567"
    assert log =~ "hello there"
  end
end
