defmodule ZamHealthWatchWeb.SmsWebhookController do
  use ZamHealthWatchWeb, :controller

  @moduledoc """
  Receives inbound SMS webhooks, shaped like Africa's Talking's inbound
  SMS callback (`from`, `to`, `text`, plus `id`/`date`/`linkId` - this
  doesn't use those last three yet; see docs/ITERATIONS.md for why).

  This controller's only job (GRASP *Controller*) is to hand the raw
  message to `Pipeline` and respond - parsing, validation, and case
  creation all happen downstream in `SmsReporting`/`Pipeline`, not here.
  """

  alias ZamHealthWatch.SmsReporting.Pipeline

  @doc """
  Always responds `200 OK`, whether or not the message turns out to be
  processable. The report is pushed into the Broadway pipeline for
  async handling and acked/rejected there, not here - a webhook provider
  expects a fast `200` regardless of downstream outcome, and returning
  anything else risks it retrying (which is exactly the kind of
  duplicate-delivery case `id`/`linkId` dedup would guard against, once
  that's built).
  """
  def create(conn, %{"from" => from, "text" => text}) do
    Pipeline.push(%{from: from, text: text})
    send_resp(conn, 200, "")
  end

  def create(conn, _params) do
    send_resp(conn, 200, "")
  end
end
