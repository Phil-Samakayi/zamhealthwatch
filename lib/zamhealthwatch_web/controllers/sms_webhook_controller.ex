defmodule ZamHealthWatchWeb.SmsWebhookController do
  use ZamHealthWatchWeb, :controller

  @moduledoc """
  Receives inbound SMS webhooks, shaped like Africa's Talking's inbound
  SMS callback (`from`, `to`, `text`, plus `id`/`date`/`linkId` - this
  doesn't use those last three yet; see docs/ITERATIONS.md for why).

  This controller's job (GRASP *Controller*) is now two-fold, and both
  halves are still just routing: first, check whether the message is a
  `PublicAlerts` subscription keyword (`SUBSCRIBE`/`STOP`), handled
  synchronously since it's a single-row write, not something that needs
  `Pipeline`'s Broadway backpressure; if it isn't, hand it to `Pipeline`
  as before. Parsing, validation, case creation, and now SMS replies all
  still happen downstream in `PublicAlerts`/`SmsReporting`/`Pipeline`,
  never here.
  """

  alias ZamHealthWatch.PublicAlerts
  alias ZamHealthWatch.SmsReporting.Pipeline

  @doc """
  Always responds `200 OK`, whether or not the message turns out to be
  processable. A recognized `PublicAlerts` keyword is handled inline
  before responding (it's one row write plus one SMS reply - fast
  enough not to need async handling); anything else is pushed into the
  Broadway pipeline for async handling and acked/rejected there. Either
  way, a webhook provider expects a fast `200` regardless of downstream
  outcome, and returning anything else risks it retrying (which is
  exactly the kind of duplicate-delivery case `id`/`linkId` dedup would
  guard against, once that's built).
  """
  def create(conn, %{"from" => from, "text" => text}) do
    case PublicAlerts.handle_inbound_sms(from, text) do
      :handled -> :ok
      :not_a_keyword -> Pipeline.push(%{from: from, text: text})
    end

    send_resp(conn, 200, "")
  end

  def create(conn, _params) do
    send_resp(conn, 200, "")
  end
end
