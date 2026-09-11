defmodule ZamHealthWatchWeb.HospitalLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.HospitalCapacity.CapacityReport

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Record hospital capacity
        <:subtitle>
          Bed occupancy, ICU status, and today's admissions, by facility. 80%+ bed occupancy is flagged near capacity, 100%+ over capacity.
        </:subtitle>
      </.header>

      <.form for={@form} id="capacity-form" phx-submit="save">
        <.input
          field={@form[:facility_id]}
          type="select"
          label="Facility"
          options={@facility_options}
          prompt="Select a facility"
        />
        <.input field={@form[:total_beds]} type="number" label="Total beds" min="1" />
        <.input field={@form[:occupied_beds]} type="number" label="Occupied beds" min="0" />
        <.input field={@form[:icu_beds_total]} type="number" label="ICU beds (total)" min="0" />
        <.input field={@form[:icu_beds_occupied]} type="number" label="ICU beds occupied" min="0" />
        <.input field={@form[:admissions_today]} type="number" label="Admissions today" min="0" />
        <.button variant="primary" phx-disable-with="Recording...">Record capacity</.button>
      </.form>

      <div class="divider" />

      <.header>
        Capacity reports
        <:subtitle>
          {@record_count} report{if @record_count != 1, do: "s"} submitted so far.
        </:subtitle>
      </.header>

      <p :if={@record_count == 0} id="no-capacity-reports" class="text-sm text-base-content/60">
        No capacity reports recorded yet.
      </p>

      <.table :if={@record_count > 0} id="capacity-reports" rows={@streams.capacity_reports}>
        <:col :let={{_id, entry}} label="Facility">{facility_name(entry, @facilities_by_id)}</:col>
        <:col :let={{_id, entry}} label="Beds">{entry.occupied_beds}/{entry.total_beds}</:col>
        <:col :let={{_id, entry}} label="Bed occupancy">
          <span class={["badge", status_badge_class(entry)]}>
            {occupancy_percent(entry)}% - {status_label(entry)}
          </span>
        </:col>
        <:col :let={{_id, entry}} label="ICU (free/total)">{icu_text(entry)}</:col>
        <:col :let={{_id, entry}} label="Admissions today">{entry.admissions_today}</:col>
        <:col :let={{_id, entry}} label="Reported">{time_ago(entry.inserted_at)}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: HospitalCapacity.subscribe_capacity_reports()

    facilities = Geography.list_facilities()
    reports = HospitalCapacity.list_capacity_reports()

    socket =
      socket
      |> assign(:facilities_by_id, Map.new(facilities, &{&1.id, &1}))
      |> assign(:facility_options, Enum.map(facilities, &{&1.name, &1.id}))
      |> assign(:record_count, length(reports))
      |> assign_form(HospitalCapacity.change_capacity_report(%CapacityReport{}))
      |> stream(:capacity_reports, reports)

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"capacity_report" => params}, socket) do
    case HospitalCapacity.record_capacity(with_reporter(params, socket)) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Capacity report recorded.")
         |> assign_form(HospitalCapacity.change_capacity_report(%CapacityReport{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_info({:created, %CapacityReport{} = report}, socket) do
    {:noreply,
     socket
     |> stream_insert(:capacity_reports, report, at: 0)
     |> update(:record_count, &(&1 + 1))}
  end

  # `reported_by_id` is never taken from client params - same pattern
  # every other LiveView in this project (`with_reporter/2`/
  # `with_requester/2`) already established.
  defp with_reporter(params, socket) do
    Map.put(params, "reported_by_id", socket.assigns.current_scope.user.id)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "capacity_report"))
  end

  defp facility_name(%CapacityReport{facility_id: facility_id}, facilities_by_id) do
    case Map.get(facilities_by_id, facility_id) do
      nil -> "Unknown facility"
      facility -> facility.name
    end
  end

  defp status_badge_class(entry) do
    case CapacityReport.capacity_status(entry) do
      :adequate -> "badge-success"
      :near_capacity -> "badge-warning"
      :over_capacity -> "badge-error"
    end
  end

  defp status_label(entry) do
    case CapacityReport.capacity_status(entry) do
      :adequate -> "Adequate"
      :near_capacity -> "Near capacity"
      :over_capacity -> "Over capacity"
    end
  end

  defp occupancy_percent(entry) do
    entry |> CapacityReport.bed_occupancy_rate() |> Kernel.*(100) |> Float.round(1)
  end

  # A dash for a facility with no ICU beds at all - `icu_occupancy_rate/1`
  # returning `nil` in that case is a real, valid state, not an error to
  # paper over with a misleading "0 free".
  defp icu_text(entry) do
    case CapacityReport.icu_occupancy_rate(entry) do
      nil -> "No ICU beds"
      _rate -> "#{CapacityReport.icu_beds_available(entry)}/#{entry.icu_beds_total}"
    end
  end
end
