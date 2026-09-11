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
  """

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
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
  code. There's no SMS reply on failure yet - that needs real outbound
  SMS delivery, which `PublicAlerts.AlertWorker` only mocks
  (`Logger.info`) so far. `SmsReporting.Pipeline` logs the reason instead.

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
end
