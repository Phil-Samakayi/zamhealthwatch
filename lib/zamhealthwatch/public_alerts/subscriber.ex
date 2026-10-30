defmodule ZamHealthWatch.PublicAlerts.Subscriber do
  @moduledoc """
  Turns "a case was reported" into a Public Alerts delivery job.

  Subscribes to `CaseManagement`'s `"cases"` PubSub topic and, on every
  `{:created, case}` broadcast, enqueues an `AlertWorker` job. Doesn't
  react to `{:updated, case}` - a case being confirmed doesn't change
  the advice the original alert already gave.

  Since Iteration 15 it also subscribes to case reclassifications, and
  enqueues a `ReclassificationAlertWorker` follow-up when a case is
  ruled out (`:not_a_case`), or when a correction reverses that - the
  people who were warned about a case are told when it turns out not
  to be one, and told again if that turns out to be wrong.

  A small, permanent `GenServer` rather than a one-off `Task`, because it
  needs to live for the app's whole lifetime and keep its PubSub
  subscription - started under `ZamHealthWatch.Application`'s
  supervision tree like everything else long-running. It's deliberately
  off in `:test` (see `config/test.exs`); tests that want to exercise it
  start their own instance with `start_supervised!/1`.
  """
  use GenServer

  require Logger

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.PublicAlerts.AlertWorker
  alias ZamHealthWatch.PublicAlerts.ReclassificationAlertWorker

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    CaseManagement.subscribe_cases()
    CaseManagement.subscribe_reclassifications()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:created, %Case{} = case_record}, state) do
    case AlertWorker.new(%{case_id: case_record.id}) |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue a public alert job: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:updated, %Case{}}, state), do: {:noreply, state}

  def handle_info({:reclassified, %Case{status: to} = case_record, from}, state)
      when to == :not_a_case or from == :not_a_case do
    job =
      ReclassificationAlertWorker.new(%{
        case_id: case_record.id,
        from: Atom.to_string(from),
        to: Atom.to_string(to)
      })

    case Oban.insert(job) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue a public alert follow-up job: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:reclassified, %Case{}, _from}, state), do: {:noreply, state}
end
