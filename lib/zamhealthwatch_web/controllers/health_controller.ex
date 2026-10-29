defmodule ZamHealthWatchWeb.HealthController do
  use ZamHealthWatchWeb, :controller

  @doc """
  A bare 200 for Render's health checks (Iteration 14).

  Routed outside the `:browser` pipeline, so a check doesn't pay for a
  session, a CSRF token, or the current-user database lookup on every
  hit, and excluded from `force_ssl` in `config/prod.exs`, since checks
  arrive over plain HTTP. Deliberately doesn't query the database: Neon's
  free tier suspends compute when idle, and a health check that woke it
  every few seconds would keep it permanently awake.
  """
  def show(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
