defmodule ZamHealthWatchWeb.NationalReportingController do
  use ZamHealthWatchWeb, :controller

  alias ZamHealthWatch.NationalReporting

  @doc """
  Streams the current national snapshot as a CSV download.

  A plain controller action, not a LiveView event - triggering a
  browser "Save As" download from inside a LiveView socket needs an
  extra JS hook/data-URL workaround for something a normal HTTP
  response already does for free via a `content-disposition: attachment`
  header. `NationalReportingLive.Index` links to this action rather
  than handling the export itself, the same "the one thing that
  genuinely needs to step outside LiveView gets a thin controller of
  its own, nothing else does" reasoning the SMS/USSD webhook
  controllers already set for inbound traffic with no browser session
  to begin with.

  Gated by the `:require_moh_admin` plug (see `UserAuth`/the router),
  the controller-pipeline equivalent of the `:require_moh_admin`
  on_mount every other MOH-only screen in this project already uses -
  same role, same "MOH-level consumption" framing the brief itself
  uses for this module.
  """
  def download(conn, _params) do
    csv = NationalReporting.export_csv()
    filename = "zamhealthwatch-national-report-#{Date.utc_today()}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end
end
