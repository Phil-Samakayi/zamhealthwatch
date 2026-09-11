defmodule ZamHealthWatchWeb.VaccinationLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Record vaccination coverage
        <:subtitle>
          Doses administered against a target population, by district, antigen, and campaign.
        </:subtitle>
      </.header>

      <.form for={@form} id="vaccination-form" phx-submit="save">
        <.input
          field={@form[:district_id]}
          type="select"
          label="District"
          options={@district_options}
          prompt="Select a district"
        />
        <.input
          field={@form[:antigen]}
          type="select"
          label="Antigen"
          options={@antigen_options}
          prompt="Select an antigen"
        />
        <.input field={@form[:campaign]} type="text" label="Campaign" placeholder="e.g. Routine - Sep 2026" />
        <.input field={@form[:doses_administered]} type="number" label="Doses administered" min="0" />
        <.input field={@form[:target_population]} type="number" label="Target population" min="1" />
        <.button variant="primary" phx-disable-with="Recording...">Record coverage</.button>
      </.form>

      <div class="divider" />

      <.header>
        Coverage records
        <:subtitle>
          {@record_count} record{if @record_count != 1, do: "s"} submitted so far.
        </:subtitle>
      </.header>

      <p :if={@record_count == 0} id="no-vaccination-records" class="text-sm text-base-content/60">
        No vaccination coverage recorded yet.
      </p>

      <.table :if={@record_count > 0} id="vaccination-records" rows={@streams.vaccination_records}>
        <:col :let={{_id, entry}} label="District">{district_name(entry, @districts_by_id)}</:col>
        <:col :let={{_id, entry}} label="Antigen">{VaccinationRecord.antigen_label(entry.antigen)}</:col>
        <:col :let={{_id, entry}} label="Campaign">{entry.campaign}</:col>
        <:col :let={{_id, entry}} label="Doses">{entry.doses_administered}</:col>
        <:col :let={{_id, entry}} label="Target">{entry.target_population}</:col>
        <:col :let={{_id, entry}} label="Coverage">
          <span class={["badge", coverage_badge_class(entry)]}>{coverage_percent(entry)}%</span>
        </:col>
        <:col :let={{_id, entry}} label="Reported">{time_ago(entry.inserted_at)}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: VaccinationMonitoring.subscribe_vaccination_records()

    districts = Geography.list_districts()
    records = VaccinationMonitoring.list_vaccination_records()

    socket =
      socket
      |> assign(:districts_by_id, Map.new(districts, &{&1.id, &1}))
      |> assign(:district_options, Enum.map(districts, &{&1.name, &1.id}))
      |> assign(:antigen_options, VaccinationRecord.antigen_options())
      |> assign(:record_count, length(records))
      |> assign_form(VaccinationMonitoring.change_vaccination_record(%VaccinationRecord{}))
      |> stream(:vaccination_records, records)

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"vaccination_record" => params}, socket) do
    case VaccinationMonitoring.record_vaccination(with_reporter(params, socket)) do
      {:ok, _record} ->
        {:noreply,
         socket
         |> put_flash(:info, "Vaccination coverage recorded.")
         |> assign_form(VaccinationMonitoring.change_vaccination_record(%VaccinationRecord{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_info({:created, %VaccinationRecord{} = record}, socket) do
    {:noreply,
     socket
     |> stream_insert(:vaccination_records, record, at: 0)
     |> update(:record_count, &(&1 + 1))}
  end

  # `reported_by_id` is never taken from client params - same pattern
  # CaseLive.Index's `with_reporter/2` and LabLive.Index's
  # `with_requester/2` already established.
  defp with_reporter(params, socket) do
    Map.put(params, "reported_by_id", socket.assigns.current_scope.user.id)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "vaccination_record"))
  end

  defp district_name(%VaccinationRecord{district_id: district_id}, districts_by_id) do
    case Map.get(districts_by_id, district_id) do
      nil -> "Unknown district"
      district -> district.name
    end
  end

  # 80%/50% thresholds are placeholders, same honestly-flagged-arbitrary
  # reasoning as PredictiveAnalytics.RiskScore's own tier cutoffs - not
  # calibrated against any real Zambia EPI target yet, revisit once real
  # coverage data exists to tune against.
  defp coverage_badge_class(entry) do
    rate = VaccinationRecord.coverage_rate(entry)

    cond do
      rate >= 0.8 -> "badge-success"
      rate >= 0.5 -> "badge-warning"
      true -> "badge-error"
    end
  end

  defp coverage_percent(entry) do
    entry |> VaccinationRecord.coverage_rate() |> Kernel.*(100) |> Float.round(1)
  end

  defp time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end
end
