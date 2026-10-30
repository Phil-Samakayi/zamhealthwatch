defmodule ZamHealthWatch.PublicAlerts.ReclassificationAlertWorker do
  @moduledoc """
  Sends alert subscribers a follow-up when a reported case is ruled out,
  or when a "ruled out" turns out to have been wrong (Iteration 15).

  Public alerts go out when a case is first *reported* (see
  `AlertWorker`), while it's still only suspected. If the lab then rules
  it out, the people who were warned deserve to hear that too, or the
  system has spread a warning it never took back. And if a correction
  reverses a "ruled out", that update was itself wrong and needs
  correcting just as plainly.

  Only those two transitions get a message - into `:not_a_case`, and out
  of it. A suspected case being confirmed doesn't: the original alert
  already told people to take precautions, and confirming it doesn't
  change that advice.

  One Oban job per transition, enqueued by `PublicAlerts.Subscriber`.
  Delivery and its retry rule are shared with `AlertWorker` through
  `PublicAlerts.deliver_to/2`.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 5

  require Logger

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.PublicAlerts

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"case_id" => case_id, "from" => from, "to" => to}}) do
    case_record = CaseManagement.get_case!(case_id)
    phones = PublicAlerts.list_subscriber_phones()

    Logger.info(
      "Public alert follow-up: case #{case_id} reclassified #{from} -> #{to} - " <>
        "notifying #{length(phones)} subscriber(s)"
    )

    PublicAlerts.deliver_to(phones, message(case_record, from, to))
  end

  @doc """
  The follow-up text for a case moving from `from` to `to` (both as
  strings, the way they arrive in a job's args).
  """
  def message(%Case{} = case_record, _from, "not_a_case") do
    "ZamHealthWatch update: the #{describe(case_record)} has been ruled out " <>
      "by laboratory testing."
  end

  def message(%Case{} = case_record, "not_a_case", to) do
    now = if to == "confirmed", do: "confirmed", else: "under investigation again"

    "ZamHealthWatch correction: we said the #{describe(case_record)} had been ruled out. " <>
      "That was wrong - the case is #{now}. Please take appropriate precautions."
  end

  defp describe(%Case{} = case_record) do
    "#{Case.disease_label(case_record.disease)} case reported at " <>
      "#{facility_name(case_record.facility_id)} on " <>
      Calendar.strftime(case_record.inserted_at, "%d %b %Y")
  end

  # Same fallback AlertWorker's own facility_name/1 uses - a missing
  # facility shouldn't stop the follow-up going out.
  defp facility_name(facility_id) do
    Geography.get_facility!(facility_id).name
  rescue
    Ecto.NoResultsError -> facility_id
  end
end
