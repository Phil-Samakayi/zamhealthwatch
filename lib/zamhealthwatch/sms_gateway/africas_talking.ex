defmodule ZamHealthWatch.SmsGateway.AfricasTalking do
  @moduledoc """
  Real outbound SMS delivery via Africa's Talking's SMS API - the
  brief's own named SMS/USSD provider, and the piece `PublicAlerts.AlertWorker`
  and `SmsWebhookController`'s own code comments already flagged as
  Logger-mocked, deliberately deferred, before this iteration.

  Only ever live when `config :zamhealthwatch, :sms_gateway` is set to
  this module - `config/runtime.exs`'s prod block does that only when
  `AFRICAS_TALKING_USERNAME`/`AFRICAS_TALKING_API_KEY` are both present
  in the environment, and falls back to `SmsGateway.Logger` (with a
  loud boot warning) otherwise. Deliberately **not** a hard `raise`
  the way missing `DATABASE_URL`/`SECRET_KEY_BASE` already are in that
  same file - a missing SMS provider degrades one feature (alerts and
  SMS replies silently become log-only again), it doesn't leave the
  app unable to start the way a missing database connection would.

  Endpoint, method, and request shape below were checked against
  Africa's Talking's own published SMS API reference this session
  (`POST https://api.africastalking.com/version1/messaging`, form body
  `username`/`to`/`message`/optional `from`, `apiKey` header) - not
  guessed at. **Not** independently verified this session: the exact
  successful-response JSON body (`SMSMessageData.Recipients[].status`)
  parsed by `handle_response/1` below, and the exact success status
  code - Africa's Talking's own docs page is JS-rendered and this
  session's web tools couldn't render it, so `handle_response/1`
  deliberately accepts *any* `2xx` status alongside the expected body
  shape rather than pinning a single guessed-at code. Same "flag what
  wasn't checked live" discipline already applied to Nx/Broadway/Oban
  in this project (see `PredictiveAnalytics`'s and `SmsReporting.Pipeline`'s
  own moduledocs) - this is the first place to look if a real send
  comes back an unexpected `{:error, ...}`.

  Request options are built through `Keyword.merge/2` with
  `Application.get_env(:zamhealthwatch, :sms_gateway_req_options, [])`
  spliced in before the real ones - empty everywhere except `:test`
  (see `config/test.exs`), where it points `Req` at a `Req.Test` stub
  instead of the real network, the standard, dependency-free way to
  test a `Req`-based client (no mocking library needed, same as
  everywhere else in this project).
  """

  @behaviour ZamHealthWatch.SmsGateway

  @impl true
  def send_sms(to, text) do
    config = Application.get_env(:zamhealthwatch, __MODULE__, [])
    username = Keyword.fetch!(config, :username)
    api_key = Keyword.fetch!(config, :api_key)
    sender_id = Keyword.get(config, :sender_id)
    base_url = Keyword.get(config, :base_url, "https://api.africastalking.com")

    form = build_form(username, to, text, sender_id)

    req_options =
      [
        form: form,
        headers: [{"apiKey", api_key}, {"accept", "application/json"}]
      ]
      |> Keyword.merge(Application.get_env(:zamhealthwatch, :sms_gateway_req_options, []))

    (base_url <> "/version1/messaging")
    |> Req.post(req_options)
    |> handle_response()
  end

  defp build_form(username, to, text, nil) do
    [username: username, to: to, message: text]
  end

  defp build_form(username, to, text, sender_id) do
    [username: username, to: to, message: text, from: sender_id]
  end

  defp handle_response(
         {:ok,
          %Req.Response{
            status: status,
            body: %{"SMSMessageData" => %{"Recipients" => [%{"status" => "Success"} | _]}}
          }}
       )
       when status in 200..299 do
    :ok
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:unexpected_response, status, body}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}
end
