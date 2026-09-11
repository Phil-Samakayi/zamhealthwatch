defmodule ZamHealthWatch.PublicAlerts.AlertWorker do
  @moduledoc """
  Delivers a public alert for a reported case to every currently
  subscribed phone number, via `SmsGateway` (real Africa's Talking
  delivery when configured, `Logger`-only otherwise - see
  `SmsGateway`'s own moduledoc).

  Before this iteration, delivery was unconditionally `Logger`-only -
  this worker's own moduledoc used to call that out as a deliberate
  stand-in for a later real integration. That integration is
  `SmsGateway` now; this worker no longer knows or cares which
  implementation is actually live, same decoupling `SmsGateway`'s own
  moduledoc describes.

  One Oban job per **case**, not per recipient - `PublicAlerts.Subscriber`
  enqueues exactly one `AlertWorker` job when a case is reported, and
  this worker loops over every subscriber inline within that one job.
  Simpler than a job-per-recipient fan-out, but a real, deliberate
  trade-off worth being direct about: if this job is retried (e.g. an
  API outage caused every send to fail, see below), every subscriber
  gets sent to again, including any who may have somehow already
  received it on an earlier partial attempt. There's no per-recipient
  delivery record to dedupe against yet. Logged here rather than
  silently accepted - revisit with a job-per-recipient design if a real
  outage ever makes duplicate alerts a real user complaint, not a
  theoretical one.

  Considered "failed" (returns `{:error, ...}`, so Oban retries the
  whole job per `max_attempts: 5`) only when **every** subscriber's
  send failed and there was at least one to send to - the shape a
  systemic outage (the SMS provider itself down) would take. A handful
  of individual failures among otherwise-successful sends (e.g. one bad
  number) are logged and left undelivered rather than retried - retrying
  the whole job over one bad number would re-send to everyone who
  already got it, the exact duplicate-delivery problem described above.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 5

  require Logger

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.PublicAlerts
  alias ZamHealthWatch.SmsGateway

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"case_id" => case_id}}) do
    case_record = CaseManagement.get_case!(case_id)
    message = alert_message(case_record)
    phones = PublicAlerts.list_subscriber_phones()

    Logger.info(
      "Public alert: #{to_string(case_record.disease)} case at facility " <>
        "#{case_record.facility_id} (case #{case_record.id}) - notifying #{length(phones)} subscriber(s)"
    )

    results = Enum.map(phones, fn phone -> {phone, SmsGateway.send_sms(phone, message)} end)

    for {phone, {:error, reason}} <- results do
      Logger.error("Public alert SMS to #{phone} failed: #{inspect(reason)}")
    end

    if results != [] and Enum.all?(results, fn {_phone, result} -> result != :ok end) do
      {:error, :all_deliveries_failed}
    else
      :ok
    end
  end

  defp alert_message(%Case{} = case_record) do
    "ZamHealthWatch alert: a #{Case.disease_label(case_record.disease)} case has been reported at " <>
      "#{facility_name(case_record.facility_id)}. Please take appropriate precautions."
  end

  # A facility could in principle disappear between the case being
  # reported and this job running (no delete UI exists yet, but nothing
  # stops one being added later) - falls back to the raw id rather than
  # letting the whole alert job crash over a display detail.
  defp facility_name(facility_id) do
    Geography.get_facility!(facility_id).name
  rescue
    Ecto.NoResultsError -> facility_id
  end
end
