defmodule ZamHealthWatch.SmsGateway do
  @moduledoc """
  A behaviour and thin dispatcher for "send this SMS to this phone
  number" - genuinely its own responsibility now that this iteration
  gives two independent contexts a real reason to send outbound SMS
  (`PublicAlerts`' subscriber broadcast, `SmsReporting`'s reporter
  reply), neither of which should own the HTTP details of whichever
  provider is configured. Same "own context for a distinct
  responsibility" call this project has made everywhere else.

  Two implementations ship with this iteration:

    * `ZamHealthWatch.SmsGateway.Logger` - logs instead of sending, the
      default everywhere except a production boot with real Africa's
      Talking credentials configured (see `config/runtime.exs`). Also
      the only implementation ever exercised in `:test` - same "mock
      delivery, log-asserted" pattern `PublicAlerts.AlertWorker` already
      established for public alerts before this iteration, now shared.
    * `ZamHealthWatch.SmsGateway.AfricasTalking` - the brief's actual
      named SMS/USSD provider, a real `Req` call. See its own moduledoc
      for what was (and wasn't) verified against Africa's Talking's
      published API reference this session.

  Which one is live is a plain `Application.get_env/3` module swap
  (`config :zamhealthwatch, :sms_gateway, ...`), not a behaviour-mocking
  library - this project hasn't reached for one anywhere else, and a
  config-swapped module is enough for the one axis that actually varies
  here (which provider, if any, really sends).
  """

  @callback send_sms(to :: String.t(), text :: String.t()) :: :ok | {:error, term()}

  @doc """
  Sends `text` to `to` via whichever `ZamHealthWatch.SmsGateway`
  implementation is configured.

  ## Examples

      iex> send_sms("+260971234567", "hello")
      :ok

  """
  def send_sms(to, text) when is_binary(to) and is_binary(text) do
    impl().send_sms(to, text)
  end

  defp impl do
    Application.get_env(:zamhealthwatch, :sms_gateway, ZamHealthWatch.SmsGateway.Logger)
  end
end
