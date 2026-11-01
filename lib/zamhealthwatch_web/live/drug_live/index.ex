defmodule ZamHealthWatchWeb.DrugLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.PredictiveAnalytics

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Record drug stock
        <:subtitle>
          Quantity on hand against a reorder level, by facility and medicine. A quantity below the reorder level is flagged as a shortage.
        </:subtitle>
      </.header>

      <div :if={@supply_alerts != []} id="supply-alerts" class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <div>
          <p class="font-semibold">Short where it's needed now</p>
          <ul class="text-sm">
            <li
              :for={alert <- @supply_alerts}
              id={"supply-alert-#{alert.facility_id}-#{alert.medicine}"}
            >
              {alert.facility_name}: {DrugStock.medicine_label(alert.medicine)} at {alert.quantity_on_hand} / {alert.reorder_level}, with {alert.case_count} {Case.disease_label(alert.disease)} {if alert.case_count == 1, do: "case", else: "cases"} in the last 4 weeks.
            </li>
          </ul>
        </div>
      </div>

      <div :if={@scope == :unassigned} class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          You haven't been assigned to a facility yet. Ask an MOH admin to assign you from
          <.link navigate={~p"/admin/users"} class="link">Manage users</.link>.
        </span>
      </div>

      <.form :if={@scope != :unassigned} for={@form} id="drug-stock-form" phx-submit="save">
        <.input
          :if={@locked_facility}
          type="text"
          name="drug_stock[facility_display]"
          label="Facility"
          value={@locked_facility.name}
          disabled
        />
        <.input
          :if={!@locked_facility}
          field={@form[:facility_id]}
          type="select"
          label="Facility"
          options={@facility_options}
          prompt="Select a facility"
        />
        <.input
          field={@form[:medicine]}
          type="select"
          label="Medicine"
          options={@medicine_options}
          prompt="Select a medicine"
        />
        <.input field={@form[:quantity_on_hand]} type="number" label="Quantity on hand" min="0" />
        <.input field={@form[:reorder_level]} type="number" label="Reorder level" min="0" />
        <.button variant="primary" phx-disable-with="Recording...">Record stock</.button>
      </.form>

      <div class="divider" />

      <.header>
        Stock records
        <:subtitle>
          {@record_count} record{if @record_count != 1, do: "s"} submitted so far.
        </:subtitle>
      </.header>

      <p :if={@record_count == 0} id="no-drug-stocks" class="text-sm text-base-content/60">
        No drug stock recorded yet.
      </p>

      <.table :if={@record_count > 0} id="drug-stocks" rows={@streams.drug_stocks}>
        <:col :let={{_id, entry}} label="Facility">{facility_name(entry, @facilities_by_id)}</:col>
        <:col :let={{_id, entry}} label="Medicine">{DrugStock.medicine_label(entry.medicine)}</:col>
        <:col :let={{_id, entry}} label="On hand">{entry.quantity_on_hand}</:col>
        <:col :let={{_id, entry}} label="Reorder level">{entry.reorder_level}</:col>
        <:col :let={{_id, entry}} label="Status">
          <span class={["badge", status_badge_class(entry)]}>{status_label(entry)}</span>
        </:col>
        <:col :let={{_id, entry}} label="Reported">{time_ago(entry.inserted_at)}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DrugAvailability.subscribe_drug_stocks()
      CaseManagement.subscribe_cases()
    end

    scope = facility_scope(socket.assigns.current_scope.user)
    facilities = Geography.list_facilities()
    stocks = list_stocks(scope)

    socket =
      socket
      |> assign(:scope, scope)
      |> assign(:locked_facility, locked_facility(scope))
      |> assign(:facilities_by_id, Map.new(facilities, &{&1.id, &1}))
      |> assign(:facility_options, Enum.map(facilities, &{&1.name, &1.id}))
      |> assign(:medicine_options, DrugStock.medicine_options())
      |> assign(:record_count, length(stocks))
      |> assign_supply_alerts()
      |> assign_form(DrugAvailability.change_drug_stock(%DrugStock{}))
      |> stream(:drug_stocks, stocks)

    {:ok, socket}
  end

  # Same role-based scope CaseLive.Index establishes (see its own
  # comment for the full reasoning) - duplicated here rather than
  # shared, same small-per-module-helper convention `with_reporter/2`
  # already set.
  defp facility_scope(%{role: :health_worker, facility_id: nil}), do: :unassigned
  defp facility_scope(%{role: :health_worker, facility_id: facility_id}), do: {:locked, facility_id}
  defp facility_scope(_user), do: :unrestricted

  defp list_stocks(:unrestricted), do: DrugAvailability.list_drug_stocks()
  defp list_stocks(:unassigned), do: []
  defp list_stocks({:locked, facility_id}), do: DrugAvailability.list_drug_stocks_by_facility(facility_id)

  defp locked_facility({:locked, facility_id}) do
    Geography.get_facility!(facility_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp locked_facility(_scope), do: nil

  defp apply_scope(params, {:locked, facility_id}), do: Map.put(params, "facility_id", facility_id)
  defp apply_scope(params, _scope), do: params

  @impl true
  def handle_event("save", %{"drug_stock" => params}, socket) do
    case socket.assigns.scope do
      :unassigned ->
        {:noreply,
         put_flash(socket, :error, "You need to be assigned to a facility before recording stock.")}

      scope ->
        scoped_params = params |> with_reporter(socket) |> apply_scope(scope)

        case DrugAvailability.record_stock(scoped_params) do
          {:ok, _stock} ->
            {:noreply,
             socket
             |> put_flash(:info, "Drug stock recorded.")
             |> assign_form(DrugAvailability.change_drug_stock(%DrugStock{}))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end
    end
  end

  # Only stock in this user's scope is added to the list (before
  # Iteration 19 every broadcast record was, so a health worker's list
  # picked up other facilities' submissions until a reload). Alerts are
  # recalculated either way, since they're scoped when assigned.
  @impl true
  def handle_info({:created, %DrugStock{} = stock}, socket) do
    socket = assign_supply_alerts(socket)

    if in_scope?(socket.assigns.scope, stock) do
      {:noreply,
       socket
       |> stream_insert(:drug_stocks, stock, at: 0)
       |> update(:record_count, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  # A new or reclassified case can start or stop an alert.
  def handle_info({event, %Case{}}, socket) when event in [:created, :updated] do
    {:noreply, assign_supply_alerts(socket)}
  end

  defp in_scope?(:unrestricted, _stock), do: true
  defp in_scope?({:locked, facility_id}, %DrugStock{facility_id: facility_id}), do: true
  defp in_scope?(_scope, _stock), do: false

  # Shortages where the medicine is needed now (Iteration 19), limited
  # to the health worker's own facility; everyone else sees them all.
  defp assign_supply_alerts(socket) do
    alerts =
      case socket.assigns.scope do
        :unrestricted ->
          PredictiveAnalytics.list_supply_alerts()

        :unassigned ->
          []

        {:locked, facility_id} ->
          Enum.filter(PredictiveAnalytics.list_supply_alerts(), &(&1.facility_id == facility_id))
      end

    assign(socket, :supply_alerts, alerts)
  end

  # `reported_by_id` is never taken from client params - same pattern
  # CaseLive.Index's `with_reporter/2`, LabLive.Index's `with_requester/2`,
  # and VaccinationLive.Index's `with_reporter/2` already established.
  defp with_reporter(params, socket) do
    Map.put(params, "reported_by_id", socket.assigns.current_scope.user.id)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "drug_stock"))
  end

  defp facility_name(%DrugStock{facility_id: facility_id}, facilities_by_id) do
    case Map.get(facilities_by_id, facility_id) do
      nil -> "Unknown facility"
      facility -> facility.name
    end
  end

  defp status_badge_class(entry) do
    if DrugStock.shortage?(entry), do: "badge-error", else: "badge-success"
  end

  defp status_label(entry) do
    if DrugStock.shortage?(entry), do: "Shortage", else: "Adequate"
  end
end
