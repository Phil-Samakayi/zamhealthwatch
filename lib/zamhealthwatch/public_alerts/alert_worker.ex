defmodule ZamHealthWatch.PublicAlerts.AlertWorker do
  @moduledoc """
  Delivers a public alert for a reported case.

  Delivery is `Logger`-only for now - a stand-in for the real Africa's
  Talking SMS/USSD integration named in the brief. Wiring that up behind
  an Oban worker now, even with mock delivery, is what actually proves
  out the risky part of this slice: alert delivery as a retryable,
  persisted background job, decoupled from the request that reported the
  case, rather than sent inline from `PublicAlerts.Subscriber`. Swapping
  the body of `perform/1` for a real `Req` call to Africa's Talking later
  shouldn't need to touch anything else in this pipeline.

  Takes a `case_id` rather than a serialized `Case` in its args and
  re-fetches it in `perform/1` - the standard Oban pattern (job args must
  round-trip through JSON anyway, and a job that runs later should see
  the case's current state, not a snapshot from when it was enqueued).
  """
  use Oban.Worker, queue: :alerts, max_attempts: 5

  require Logger

  alias ZamHealthWatch.CaseManagement

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"case_id" => case_id}}) do
    case_record = CaseManagement.get_case!(case_id)

    Logger.info(
      "PUBLIC ALERT (mock delivery): #{to_string(case_record.disease)} case reported " <>
        "at facility #{case_record.facility_id} (case #{case_record.id})"
    )

    :ok
  end
end
