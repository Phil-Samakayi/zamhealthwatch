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
  Reports a case from an inbound SMS.

  Expects the fixed grammar `REPORT <DISEASE> <FACILITY_CODE>`
  (case-insensitive, e.g. `"report cholera UTH"`) - deliberately the
  smallest possible grammar rather than free text (no NLP/parsing risk
  worth taking on for a first cut) or USSD's guided, stateful menu flow
  (a structurally different, session-based integration - a real gap,
  logged rather than half-built here; see docs/ITERATIONS.md).

  Returns `{:ok, case}` on success, or `{:error, reason}` for any of:
  unparseable text, an unrecognized disease, or an unknown facility
  code. `SmsReporting.Pipeline` logs the reason either way and, as of
  this iteration, also texts the reporter back via `confirmation_message/1`
  and `SmsGateway.send_sms/2`.

  ## Examples

      iex> report_from_sms("+260971234567", "REPORT CHOLERA UTH")
      {:ok, %Case{}}

      iex> report_from_sms("+260971234567", "not a report")
      {:error, :unrecognized_format}

  """
  def report_from_sms(from, text) when is_binary(from) and is_binary(text) do
    with {:ok, %{disease: disease, facility_code: code}} <- parse_report(text),
         {:ok, facility} <- fetch_facility(code),
         {:ok, user} <- Accounts.find_or_create_sms_reporter(from) do
      CaseManagement.create_case(%{
        disease: disease,
        facility_id: facility.id,
        reported_by_id: user.id
      })
    end
  end

  defp parse_report(text) do
    case text |> String.trim() |> String.upcase() |> String.split(~r/\s+/, trim: true) do
      ["REPORT", disease_token, facility_code] ->
        case Map.fetch(@disease_aliases, disease_token) do
          {:ok, disease} -> {:ok, %{disease: disease, facility_code: facility_code}}
          :error -> {:error, {:unknown_disease, disease_token}}
        end

      _ ->
        {:error, :unrecognized_format}
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

  Covers every reason `report_from_sms/2` can actually return: the
  three deliberately-recognized parse/lookup failures above, plus a
  generic fallback for whatever `CaseManagement.create_case/1` or
  `Accounts.find_or_create_sms_reporter/1` might still reject (e.g. a
  changeset error neither of those two functions currently produces in
  practice, but nothing guarantees never will) - a reporter texting in
  from a low-end phone deserves *some* reply rather than silence just
  because this module didn't anticipate the exact failure shape.

  ## Examples

      iex> confirmation_message({:error, :unrecognized_format})
      "Sorry, we couldn't read that report. Text: REPORT <DISEASE> <FACILITY CODE>, e.g. REPORT CHOLERA UTH."

  """
  def confirmation_message({:ok, %Case{} = case_record}) do
    "ZamHealthWatch: thanks - your #{Case.disease_label(case_record.disease)} report at " <>
      "#{facility_name(case_record.facility_id)} was recorded."
  end

  def confirmation_message({:error, :unrecognized_format}) do
    "Sorry, we couldn't read that report. Text: REPORT <DISEASE> <FACILITY CODE>, e.g. REPORT CHOLERA UTH."
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
