defmodule ZamHealthWatchWeb.UssdWebhookController do
  use ZamHealthWatchWeb, :controller

  @moduledoc """
  Receives inbound USSD session requests, shaped like Africa's
  Talking's USSD callback (`sessionId`, `serviceCode`, `phoneNumber`,
  `text`).

  Doesn't use `sessionId` or `serviceCode` - see `UssdReporting`'s own
  moduledoc for why the whole session is reconstructed from `text`
  alone on every request, with nothing tracked by `sessionId`.

  This controller owns exactly the one thing Africa's Talking's USSD
  protocol demands that `UssdReporting` shouldn't have to know about:
  the response must be `text/plain`, prefixed with `CON ` to keep the
  session open (the gateway will prompt the user again and send their
  next digit back in a follow-up request) or `END ` to close it (the
  gateway shows this as the final screen and the session is over).
  `UssdReporting.handle_session/2` returns plain `{:continue, text}` /
  `{:end, text}` tuples; turning that into the wire format is this
  controller's whole job - GRASP *Controller* again, same split
  `SmsWebhookController` already keeps from `PublicAlerts`/`SmsReporting`.
  """

  alias ZamHealthWatch.UssdReporting

  @doc """
  Always responds `200 OK` with a `text/plain` body starting `CON ` or
  `END `, whatever `UssdReporting.handle_session/2` returns - same
  "the gateway expects a well-formed response regardless of outcome"
  reasoning `SmsWebhookController.create/2` already documents for `200`,
  except here the *shape* of a well-formed response is dictated by the
  USSD protocol itself (a non-text/plain or wrongly-prefixed body is
  what a malformed response looks like to Africa's Talking, not a
  missing status code).
  """
  def create(conn, %{"phoneNumber" => phone, "text" => text}) do
    {marker, body} =
      case UssdReporting.handle_session(phone, text) do
        {:continue, prompt} -> {"CON", prompt}
        {:end, message} -> {"END", message}
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "#{marker} #{body}")
  end

  def create(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "END Sorry, something went wrong. Please try again.")
  end
end
