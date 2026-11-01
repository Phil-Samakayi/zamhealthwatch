defmodule ZamHealthWatch.SmsReporting do
  @moduledoc """
  The SMS Reporting context.

  Owns turning one inbound SMS/USSD-shaped message (`from` phone number
  + `text` body) into a `CaseManagement.Case`, the same underlying
  operation `CaseLive.Index`'s web form performs - this is the second,
  independent entry point onto it that Section 5 of the project brief
  calls out (GRASP *Controller*: "an SMS report comes in" gets one clear
  entry point coordinating the work, not logic scattered across the
  ingestion pipeline).

  This module holds the actual parsing/orchestration logic
  (`report_from_sms/2`); `SmsReporting.Producer` and
  `SmsReporting.Pipeline` are the Broadway wiring that feeds it from a
  webhook. Kept separate so the business logic - the part worth testing
  thoroughly - doesn't depend on Broadway being involved at all, same
  spirit as `CaseManagement`'s functions not depending on `CaseLive.Index`.

  `confirmation_message/1` is the other half of the gap this module's
  own `report_from_sms/2` doc used to call out ("there's no SMS reply on
  failure yet - that needs real outbound SMS delivery"): given exactly
  what `report_from_sms/2` returned, it answers what to text the
  reporter back. Kept on this module rather than `SmsReporting.Pipeline`
  (Information Expert - this module already knows what every
  `report_from_sms/2` result means; `Pipeline` shouldn't have to). Sent
  via `SmsGateway.send_sms/2` from `Pipeline.handle_message/3`, which is
  the one place that has both the outcome and the reporter's `from`
  number.
  """

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Geography

  @disease_aliases %{
    "CHOLERA" => :cholera,
    "MALARIA" => :malaria,
    "TYPHOID" => :typhoid,
    "COVID19" => :covid19,
    "COVID" => :covid19,
    "MEASLES" => :measles
  }

  @doc """
  Reports a case from an inbound SMS, sent from phone number `from`.

  **Only registered reporters can report (Iteration 21).** `from` must
  be the phone number of a user with a role, entered by an MOH admin on
  `/admin/users`. Anything else is refused with
  `:unregistered_number` before the text is even read, and no account is
  created. Before this, any phone could report a case at any facility,
  and since every new case sends a public alert, any stranger could
  have sent a false outbreak alert to every subscriber. SMS reporting
  exists for health workers at facilities with poor internet, so it
  carries the same trust and the same rules as the web app.

  The grammar (case-insensitive, extra spaces ignored):

    * `REPORT <DISEASE>` - a health worker's report, recorded at their
      own facility. This is the usual case.
    * `REPORT <DISEASE> <FACILITY_CODE>` - a health worker may add their
      own facility's code (any other code is refused with
      `{:wrong_facility, code, own_code}`, the same rule the web form
      enforces); every other role must give one, since they have no
      facility of their own (`:facility_code_required`).

  Returns `{:ok, case}`, or `{:error, reason}` for an unregistered
  number, a health worker with no facility (`:no_facility`), unreadable
  text, an unknown disease, or a wrong, missing, or unknown facility
  code. `SmsReporting.Pipeline` texts the reporter back either way, via
  `confirmation_message/1`.

  ## Examples

      iex> report_from_sms(registered_health_worker_phone, "REPORT CHOLERA")
      {:ok, %Case{}}

      iex> report_from_sms("+260970000000", "REPORT CHOLERA UTH")
      {:error, :unregistered_number}

  """
  def report_from_sms(from, text) when is_binary(from) and is_binary(text) do
    with {:ok, reporter} <- fetch_reporter(from),
         {:ok, %{disease: disease, facility_code: code}} <- parse_report(text),
         {:ok, facility} <- resolve_facility(reporter, code) do
      CaseManagement.create_case(%{
        disease: disease,
        facility_id: facility.id,
        reported_by_id: reporter.id
      })
    end
  end

  @doc """
  What kind of reporter `phone` belongs to, for USSD's menu to decide
  its next step (Iteration 21):

    * `:unregistered` - can't report at all.
    * `:own_facility` - a health worker, whose reports go to their own
      facility, so there's no facility code to ask for.
    * `:names_facility` - any other role, which must name the facility.
  """
  def reporter_kind(phone) when is_binary(phone) do
    case fetch_reporter(phone) do
      {:ok, %{role: :health_worker}} -> :own_facility
      {:ok, _reporter} -> :names_facility
      {:error, :unregistered_number} -> :unregistered
    end
  end

  defp fetch_reporter(phone) do
    case Accounts.get_user_by_phone(phone) do
      %{role: role} = user when not is_nil(role) -> {:ok, user}
      _unregistered -> {:error, :unregistered_number}
    end
  end

  # A health worker reports for their own facility, as on the web; any
  # other role names the facility.
  defp resolve_facility(%{role: :health_worker, facility_id: nil}, _code),
    do: {:error, :no_facility}

  defp resolve_facility(%{role: :health_worker, facility_id: facility_id}, code) do
    case own_facility(facility_id) do
      nil -> {:error, :no_facility}
      %{code: own_code} = facility when code in [nil, own_code] -> {:ok, facility}
      %{code: own_code} -> {:error, {:wrong_facility, code, own_code}}
    end
  end

  defp resolve_facility(_reporter, nil), do: {:error, :facility_code_required}
  defp resolve_facility(_reporter, code), do: fetch_facility(code)

  defp own_facility(facility_id) do
    Geography.get_facility!(facility_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp parse_report(text) do
    case text |> String.trim() |> String.upcase() |> String.split(~r/\s+/, trim: true) do
      ["REPORT", disease_token] ->
        parse_disease(disease_token, nil)

      ["REPORT", disease_token, facility_code] ->
        parse_disease(disease_token, facility_code)

      _ ->
        {:error, :unrecognized_format}
    end
  end

  defp parse_disease(disease_token, facility_code) do
    case Map.fetch(@disease_aliases, disease_token) do
      {:ok, disease} -> {:ok, %{disease: disease, facility_code: facility_code}}
      :error -> {:error, {:unknown_disease, disease_token}}
    end
  end

  defp fetch_facility(code) do
    case Geography.get_facility_by_code(code) do
      nil -> {:error, {:unknown_facility, code}}
      facility -> {:ok, facility}
    end
  end

  @doc """
  Returns the SMS reply text for a given `report_from_sms/2` result.

  Covers every reason `report_from_sms/2` can actually return - the
  registration and facility checks (Iteration 21) and the parse/lookup
  failures - plus a generic fallback for whatever
  `CaseManagement.create_case/1` might still reject (a changeset error
  it doesn't produce in practice today, but nothing guarantees never
  will). A reporter texting in from a low-end phone deserves *some*
  reply rather than silence just because this module didn't anticipate
  the exact failure shape.

  An unregistered number gets a reply too. That costs an SMS per
  message from a stranger, but a health worker whose number simply
  hasn't been registered yet needs to know why nothing happened.

  ## Examples

      iex> confirmation_message({:error, :unregistered_number})
      "This number isn't registered to report cases on ZamHealthWatch. ..."

  """
  def confirmation_message({:ok, %Case{} = case_record}) do
    "ZamHealthWatch: thanks - your #{Case.disease_label(case_record.disease)} report at " <>
      "#{facility_name(case_record.facility_id)} was recorded."
  end

  def confirmation_message({:error, :unregistered_number}) do
    "This number isn't registered to report cases on ZamHealthWatch. " <>
      "Ask your MOH administrator to add it to your account."
  end

  def confirmation_message({:error, :no_facility}) do
    "Your account has no facility yet, so we couldn't record the report. " <>
      "Ask your MOH administrator to assign one."
  end

  def confirmation_message({:error, :facility_code_required}) do
    "Please include the facility code: REPORT <DISEASE> <FACILITY CODE>, e.g. REPORT CHOLERA UTH."
  end

  def confirmation_message({:error, {:wrong_facility, code, own_code}}) do
    "You can only report cases at your own facility (#{own_code}), not #{code}. " <>
      "Text: REPORT <DISEASE>, e.g. REPORT CHOLERA."
  end

  def confirmation_message({:error, :unrecognized_format}) do
    "Sorry, we couldn't read that report. Text: REPORT <DISEASE>, e.g. REPORT CHOLERA. " <>
      "District and national staff add a facility code: REPORT CHOLERA UTH."
  end

  def confirmation_message({:error, {:unknown_disease, disease_token}}) do
    "Sorry, \"#{disease_token}\" isn't a disease ZamHealthWatch tracks yet."
  end

  def confirmation_message({:error, {:unknown_facility, code}}) do
    "Sorry, \"#{code}\" isn't a facility code ZamHealthWatch recognizes."
  end

  def confirmation_message({:error, _other}) do
    "Sorry, we couldn't record that report. Please try again or contact your facility."
  end

  # Same "don't let a display-only lookup crash the whole flow" fallback
  # AlertWorker.facility_name/1 already applies.
  defp facility_name(facility_id) do
    Geography.get_facility!(facility_id).name
  rescue
    Ecto.NoResultsError -> facility_id
  end
end
