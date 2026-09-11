defmodule ZamHealthWatchWeb.DrugLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.Geography

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

      <.form for={@form} id="drug-stock-form" phx-submit="save">
        <.input
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
    if connected?(socket), do: DrugAvailability.subscribe_drug_stocks()

    facilities = Geography.list_facilities()
    stocks = DrugAvailability.list_drug_stocks()

    socket =
      socket
      |> assign(:facilities_by_id, Map.new(facilities, &{&1.id, &1}))
      |> assign(:facility_options, Enum.map(facilities, &{&1.name, &1.id}))
      |> assign(:medicine_options, DrugStock.medicine_options())
      |> assign(:record_count, length(stocks))
      |> assign_form(DrugAvailability.change_drug_stock(%DrugStock{}))
      |> stream(:drug_stocks, stocks)

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"drug_stock" => params}, socket) do
    case DrugAvailability.record_stock(with_reporter(params, socket)) do
      {:ok, _stock} ->
        {:noreply,
         socket
         |> put_flash(:info, "Drug stock recorded.")
         |> assign_form(DrugAvailability.change_drug_stock(%DrugStock{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_info({:created, %DrugStock{} = stock}, socket) do
    {:noreply,
     socket
     |> stream_insert(:drug_stocks, stock, at: 0)
     |> update(:record_count, &(&1 + 1))}
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
