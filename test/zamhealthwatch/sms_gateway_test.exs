defmodule ZamHealthWatch.SmsGatewayTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZamHealthWatch.SmsGateway

  test "send_sms/2 dispatches to the configured implementation" do
    original_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_level) end)

    # No :sms_gateway override here - config/config.exs's default
    # (ZamHealthWatch.SmsGateway.Logger) is what every test in this
    # project runs under, same as this one.
    log =
      capture_log(fn ->
        assert :ok = SmsGateway.send_sms("+260971234567", "hello")
      end)

    assert log =~ "SMS (mock delivery)"
  end
end
