defmodule ZamHealthWatchWeb.PortalLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.LabReporting

  @recent_limit 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {if @facility, do: @facility.name, else: "Your facility"}
        <:subtitle>
          <span :if={@facility}>
            Recent activity at your facility, and shortcuts to report something new.
          </span>
          <span :if={!@facility}>You haven't been assigned to a facility yet.</span>
        </:subtitle>
      </.header>

      <div :if={@correction_notice_count > 0} id="correction-notice" class="alert alert-warning mt-4">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <span>
          {if @correction_notice_count == 1,
            do: "A result on a test you requested has been corrected.",
            else: "#{@correction_notice_count} results on tests you requested have been corrected."}
          <.link href={~p"/labs"} class="link">Review on the lab screen</.link>
        </span>
      </div>

      <div :if={!@facility} class="alert alert-info mt-4">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          Ask an MOH admin to assign you to a facility from
          <.link navigate={~p"/admin/users"} class="link">Manage users</.link>. In the meantime you
          can still <.link navigate={~p"/cases"} class="link">report a case</.link>
          or check <.link navigate={~p"/guidance"} class="link">guidance</.link>.
        </span>
      </div>

      <div :if={@facility} class="space-y-6 mt-4">
        <div class="flex flex-wrap gap-2">
          <.link navigate={~p"/cases"} class="btn btn-sm btn-primary">Report a case</.link>
          <.link navigate={~p"/hospitals"} class="btn btn-sm">Record capacity</.link>
          <.link navigate={~p"/drugs"} class="btn btn-sm">Record drug stock</.link>
          <.link navigate={~p"/guidance"} class="btn btn-sm">Guidance</.link>
        </div>

        <div>
          <.header>Hospital capacity</.header>
          <p :if={!@capacity_status} id="no-capacity-report" class="text-sm text-base-content/60">
            No capacity reports yet.
          </p>
          <span :if={@capacity_status} class={["badge", capacity_badge_class(@capacity_status)]}>
            {capacity_label(@capacity_status)}
          </span>
        </div>

        <div>
          <.header>
            Recent cases
            <:subtitle>The {length(@recent_cases)} most recently reported, newest first.</:subtitle>
          </.header>
          <p :if={@recent_cases == []} id="no-recent-cases" class="text-sm text-base-content/60">
            No cases reported at this facility yet.
          </p>
          <.table :if={@recent_cases != []} id="portal-recent-cases" rows={@recent_cases}>
            <:col :let={case_record} label="Disease">
              {Case.disease_label(case_record.disease)}
            </:col>
            <:col :let={case_record} label="Status">
              {Phoenix.Naming.humanize(case_record.status)}
            </:col>
            <:col :let={case_record} label="Reported">{time_ago(case_record.inserted_at)}</:col>
          </.table>
        </div>

        <div>
          <.header>
            Recent drug stock
            <:subtitle>The {length(@recent_stocks)} most recent submissions, newest first.</:subtitle>
          </.header>
          <p :if={@recent_stocks == []} id="no-recent-stocks" class="text-sm text-base-content/60">
            No drug stock recorded at this facility yet.
          </p>
          <.table :if={@recent_stocks != []} id="portal-recent-stocks" rows={@recent_stocks}>
            <:col :let={stock} label="Medicine">{DrugStock.medicine_label(stock.medicine)}</:col>
            <:col :let={stock} label="On hand">{stock.quantity_on_hand}</:col>
            <:col :let={stock} label="Status">
              <span class={["badge", stock_badge_class(stock)]}>{stock_status_label(stock)}</span>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    facility_id = socket.assigns.current_scope.user.facility_id

    if connected?(socket) and facility_id do
      CaseManagement.subscribe_cases()
      DrugAvailability.subscribe_drug_stocks()
      HospitalCapacity.subscribe_capacity_reports()
    end

    # Shown whether or not the user has a facility: anyone can request a
    # lab test, so anyone can have a corrected result waiting. Counted
    # once on mount - acknowledging happens on the lab screen, which
    # shows the notices themselves and keeps them live.
    correction_notice_count =
      socket.assigns.current_scope.user.id
      |> LabReporting.list_correction_notices()
      |> length()

    {:ok,
     socket
     |> assign(:correction_notice_count, correction_notice_count)
     |> assign_portal(facility_id)}
  end

  # Only recomputes when the event is actually about this viewer's own
  # facility - a case/stock/capacity event for every other facility in
  # the system is noise this LiveView has no reason to react to, unlike
  # EpidemiologyLive.Index/RiskLive.Index, which deliberately recompute
  # on *any* event because they aggregate across every facility.
  @impl true
  def handle_info({_action, %Case{facility_id: facility_id}}, socket) do
    {:noreply, maybe_refresh(socket, facility_id)}
  end

  def handle_info({_action, %DrugStock{facility_id: facility_id}}, socket) do
    {:noreply, maybe_refresh(socket, facility_id)}
  end

  def handle_info({_action, %CapacityReport{facility_id: facility_id}}, socket) do
    {:noreply, maybe_refresh(socket, facility_id)}
  end

  defp maybe_refresh(socket, facility_id) do
    if facility_id == socket.assigns.facility_id do
      assign_portal(socket, facility_id)
    else
      socket
    end
  end

  defp assign_portal(socket, nil) do
    socket
    |> assign(:facility_id, nil)
    |> assign(:facility, nil)
    |> assign(:recent_cases, [])
    |> assign(:recent_stocks, [])
    |> assign(:capacity_status, nil)
  end

  defp assign_portal(socket, facility_id) do
    capacity_report = HospitalCapacity.latest_capacity_by_facility() |> Map.get(facility_id)

    socket
    |> assign(:facility_id, facility_id)
    |> assign(:facility, fetch_facility(facility_id))
    |> assign(:recent_cases, recent(CaseManagement.list_cases_by_facility(facility_id)))
    |> assign(:recent_stocks, recent(DrugAvailability.list_drug_stocks_by_facility(facility_id)))
    |> assign(:capacity_status, capacity_report && CapacityReport.capacity_status(capacity_report))
  end

  defp recent(records), do: Enum.take(records, @recent_limit)

  # A user's `facility_id` could in principle point at a since-deleted
  # facility (no delete UI exists yet, but nothing stops one being
  # added later, and `facility_id` isn't a real FK constraint on
  # `users` - see Iteration 0's decision log) - same "don't let a
  # display-only lookup crash the whole page" fallback
  # `AlertWorker.facility_name/1` already applies, just returning `nil`
  # (this page's own "no facility" state) instead of a placeholder
  # string, since there's a whole empty state built for exactly that.
  defp fetch_facility(facility_id) do
    Geography.get_facility!(facility_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp capacity_label(:adequate), do: "Adequate"
  defp capacity_label(:near_capacity), do: "Near capacity"
  defp capacity_label(:over_capacity), do: "Over capacity"

  defp capacity_badge_class(:adequate), do: "badge-success"
  defp capacity_badge_class(:near_capacity), do: "badge-warning"
  defp capacity_badge_class(:over_capacity), do: "badge-error"

  defp stock_status_label(stock), do: if(DrugStock.shortage?(stock), do: "Shortage", else: "Adequate")
  defp stock_badge_class(stock), do: if(DrugStock.shortage?(stock), do: "badge-error", else: "badge-success")
end
