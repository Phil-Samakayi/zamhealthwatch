defmodule ZamHealthWatchWeb.WebhookToken do
  @moduledoc """
  Checks that an inbound SMS or USSD webhook really comes from the
  provider (Iteration 22).

  `/webhooks/sms` and `/webhooks/ussd` take no login - Africa's Talking
  can't log in - so without a check, anyone who found the URL could post
  fake reports or subscribe numbers. Africa's Talking doesn't sign its
  callbacks, so the check is a shared secret in the callback URL itself:
  the URL entered in the Africa's Talking dashboard is
  `https://<host>/webhooks/sms?token=<secret>`, and a request whose
  `token` doesn't match is refused with `403`. The Community Health
  Toolkit, an open-source health platform, secures its Africa's Talking
  callbacks the same way.

  Configured by `config :zamhealthwatch, :webhook_token`:

    * a string - the secret every request must carry (production, from
      `WEBHOOK_TOKEN`).
    * `:missing` - production without `WEBHOOK_TOKEN` set: every request
      is refused. Failing closed is deliberate; an open webhook is the
      problem this exists to fix.
    * `nil` - no check (development and tests), so webhooks can still be
      tried locally with `curl`.

  Only the query string is read, never the form body the provider
  posts, and the comparison is constant-time. `token` is also filtered
  out of request logs (`:filter_parameters` in `config/config.exs`).
  """

  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:zamhealthwatch, :webhook_token) do
      nil ->
        conn

      :missing ->
        Logger.error("Webhook refused: WEBHOOK_TOKEN isn't set, so no request can be verified.")
        refuse(conn)

      expected when is_binary(expected) ->
        conn = fetch_query_params(conn)

        case conn.query_params["token"] do
          given when is_binary(given) ->
            if Plug.Crypto.secure_compare(given, expected), do: conn, else: refuse(conn)

          _missing ->
            refuse(conn)
        end
    end
  end

  defp refuse(conn) do
    conn
    |> send_resp(403, "")
    |> halt()
  end
end
