defmodule ZamHealthWatch.UssdReporting do
  @moduledoc """
  The USSD Reporting context.

  Closes the second, previously-deferred SMS/USSD gap: a guided,
  stateful, multi-step USSD menu session (`*384#`-style), distinct from
  `SmsReporting`'s one-shot `REPORT <DISEASE> <FACILITY_CODE>` SMS
  grammar and `PublicAlerts.handle_inbound_sms/2`'s `SUBSCRIBE`/`STOP`
  keywords - both of those are a single inbound message with no notion
  of "what step is this phone number on". A USSD session is a back-and-
  forth: the gateway (Africa's Talking) holds the session open across
  several requests from the same phone, each one carrying the next
  menu digit the user pressed, until the application responds with a
  final (not "continue") message.

  No session state is persisted anywhere in this app - no `GenServer`,
  ETS table, or database-backed session row. Africa's Talking's USSD
  protocol sends the *entire* accumulated input history on every
  request in `text` (digits the user has pressed so far, joined by
  `*` - e.g. `"1*2*UTH"` on the third request of a report), not just
  the latest keypress. That means the whole menu state can be
  reconstructed by parsing `text` alone, fresh, on every single
  request - `handle_session/2` is a pure function of `(phone, text)`,
  nothing else. Simpler than tracking "where is this phone number in
  its session" as mutable state anywhere, and there is no real use case
  yet for anything a session row would add (resuming an abandoned
  session, for instance) - same "no lifecycle without a real use case"
  call every other single-purpose piece of this project already makes.

  Reuses `SmsReporting.report_from_sms/2` and `SmsReporting.confirmation_message/1`
  for the actual report once a disease and facility code have been
  chosen, and `PublicAlerts.subscribe/1`/`unsubscribe/1` for the
  subscription options, rather than duplicating either context's logic
  here. This context's only real job is translating numeric menu
  choices into the same inputs those contexts already accept and know
  how to validate - Information Expert again: `SmsReporting` already
  knows what a disease token or facility code means, `PublicAlerts`
  already knows what a subscription is, and neither needs to know a
  USSD menu exists.

  `UssdWebhookController` is the only caller, and the only place that
  knows about Africa's Talking's wire format (`CON `/`END ` prefixes,
  `text/plain`) - this module returns plain `{:continue, text}` or
  `{:end, text}` tuples and stays completely ignorant of that, same
  "transport detail belongs to the controller" split
  `SmsWebhookController` already keeps from `PublicAlerts`/`SmsReporting`.
  """

  alias ZamHealthWatch.PublicAlerts
  alias ZamHealthWatch.SmsReporting

  @disease_menu %{
    "1" => "CHOLERA",
    "2" => "MALARIA",
    "3" => "TYPHOID",
    "4" => "COVID19",
    "5" => "MEASLES"
  }

  @main_menu """
  Welcome to ZamHealthWatch.
  1. Report a case
  2. Subscribe to alerts
  3. Unsubscribe from alerts
  """

  @disease_prompt """
  Select disease:
  1. Cholera
  2. Malaria
  3. Typhoid
  4. COVID-19
  5. Measles
  """

  @facility_prompt "Enter facility code (e.g. UTH):"

  @invalid_selection "Invalid selection. Please try again."

  @subscribe_reply "You're subscribed to ZamHealthWatch public health alerts."
  @unsubscribe_reply "You've been unsubscribed from ZamHealthWatch public health alerts."

  @doc """
  Handles one step of a USSD session.

  `text` is Africa's Talking's full accumulated input for this
  session, exactly as the gateway sends it (e.g. `""` on the very
  first request, `"1"` after choosing "Report a case", `"1*2*UTH"`
  after also choosing Malaria and typing a facility code). Returns
  `{:continue, prompt}` when the session should stay open (the caller
  is expected to reply with a `CON `-prefixed response showing
  `prompt`), or `{:end, message}` when it's over (an `END `-prefixed
  final response).

  ## Examples

      iex> handle_session("+260971234567", "")
      {:continue, "Welcome to ZamHealthWatch...."}

      iex> handle_session("+260971234567", "2")
      {:end, "You're subscribed to ZamHealthWatch public health alerts."}

  """
  def handle_session(phone, text) when is_binary(phone) and is_binary(text) do
    text
    |> String.split("*", trim: true)
    |> route(phone)
  end

  defp route([], _phone), do: {:continue, @main_menu}

  defp route(["1"], _phone), do: {:continue, @disease_prompt}

  defp route(["1", disease_digit], _phone) do
    if Map.has_key?(@disease_menu, disease_digit) do
      {:continue, @facility_prompt}
    else
      {:end, @invalid_selection}
    end
  end

  defp route(["1", disease_digit, facility_code], phone) do
    case Map.fetch(@disease_menu, disease_digit) do
      {:ok, disease_token} ->
        result = SmsReporting.report_from_sms(phone, "REPORT #{disease_token} #{facility_code}")
        {:end, SmsReporting.confirmation_message(result)}

      :error ->
        {:end, @invalid_selection}
    end
  end

  defp route(["2"], phone) do
    {:ok, _subscriber} = PublicAlerts.subscribe(phone)
    {:end, @subscribe_reply}
  end

  defp route(["3"], phone) do
    :ok = PublicAlerts.unsubscribe(phone)
    {:end, @unsubscribe_reply}
  end

  defp route(_other, _phone), do: {:end, @invalid_selection}
end
