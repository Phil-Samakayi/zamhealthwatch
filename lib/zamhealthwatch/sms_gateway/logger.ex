defmodule ZamHealthWatch.SmsGateway.Logger do
  @moduledoc """
  Logger-only `SmsGateway` implementation - logs what would have been
  sent instead of actually sending it, same spirit as
  `PublicAlerts.AlertWorker`'s pre-this-iteration mock delivery.

  The default in every environment (`config/config.exs`) except a
  production boot with real Africa's Talking credentials set (see
  `config/runtime.exs`'s prod block) - and the *only* implementation
  ever exercised in `:test`, deliberately: no HTTP call, no network
  flakiness, no real phone number ever contacted by a test run.
  Callers that need to assert an SMS was "sent" do it the same way
  `PublicAlerts.AlertWorkerTest` already asserted its old mock delivery
  - `ExUnit.CaptureLog` around a temporarily raised `Logger` level (see
  that test's own comment on why the raise-then-restore dance is
  needed under this project's `:warning` test log level).
  """

  @behaviour ZamHealthWatch.SmsGateway

  require Logger

  @impl true
  def send_sms(to, text) do
    Logger.info("SMS (mock delivery) to=#{to} text=#{inspect(text)}")
    :ok
  end
end
