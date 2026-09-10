defmodule ZamHealthWatch.PublicAlerts.Subscriber do
  @moduledoc """
  Turns "a case was reported" into a Public Alerts delivery job.

  Subscribes to `CaseManagement`'s `"cases"` PubSub topic and, on every
  `{:created, case}` broadcast, enqueues an `AlertWorker` job. Doesn't
  react to `{:updated, case}` - alerting on every later status change
  (e.g. a case moving from `:suspected` to `:resolved`) isn't part of
  this slice; only the initial report triggers an alert for now.

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

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    CaseManagement.subscribe_cases()
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
end
