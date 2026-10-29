defmodule ZamHealthWatchWeb.VaccinationLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

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

      <div :if={@scope == :unassigned} class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          You haven't been assigned to a facility yet. Ask an MOH admin to assign you from
          <.link navigate={~p"/admin/users"} class="link">Manage users</.link>.
        </span>
      </div>

      <div :if={@scope == :no_district} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <span>Your facility doesn't have a district set yet - ask an MOH admin to add one.</span>
      </div>

      <.form
        :if={@scope not in [:unassigned, :no_district]}
        for={@form}
        id="vaccination-form"
        phx-submit="save"
      >
        <.input
          :if={@locked_district}
          type="text"
          name="vaccination_record[district_display]"
          label="District"
          value={@locked_district.name}
          disabled
        />
        <.input
          :if={!@locked_district}
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

    scope = socket.assigns.current_scope.user |> facility_scope() |> district_scope()

    districts = Geography.list_districts()
    records = list_records(scope)

    socket =
      socket
      |> assign(:scope, scope)
      |> assign(:locked_district, locked_district(scope, districts))
      |> assign(:districts_by_id, Map.new(districts, &{&1.id, &1}))
      |> assign(:district_options, Enum.map(districts, &{&1.name, &1.id}))
      |> assign(:antigen_options, VaccinationRecord.antigen_options())
      |> assign(:record_count, length(records))
      |> assign_form(VaccinationMonitoring.change_vaccination_record(%VaccinationRecord{}))
      |> stream(:vaccination_records, records)

    {:ok, socket}
  end

  # Same role-based scope CaseLive.Index/DrugLive.Index/HospitalLive.Index/
  # LabLive.Index already establish (see CaseLive.Index's own comment
  # for the full reasoning) - duplicated here, same convention.
  defp facility_scope(%{role: :health_worker, facility_id: nil}), do: :unassigned
  defp facility_scope(%{role: :health_worker, facility_id: facility_id}), do: {:locked, facility_id}
  defp facility_scope(_user), do: :unrestricted

  # `VaccinationRecord` is district-grain, not facility-grain (see
  # VaccinationMonitoring's moduledoc), so this screen immediately
  # narrows a `{:locked, facility_id}` scope down to the *district that
  # facility sits in*. `district_id` on `Geography.Facility` is
  # optional (no facility-management UI yet to guarantee it's set), so
  # a facility with no district on record gets its own distinct
  # `:no_district` state rather than silently falling back to either
  # "show everything" or "show nothing with the wrong explanation".
  defp district_scope(:unrestricted), do: :unrestricted
  defp district_scope(:unassigned), do: :unassigned

  defp district_scope({:locked, facility_id}) do
    case fetch_facility(facility_id) do
      %{district_id: district_id} when not is_nil(district_id) -> {:locked, district_id}
      _no_district -> :no_district
    end
  end

  defp fetch_facility(facility_id) do
    Geography.get_facility!(facility_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp list_records(:unrestricted), do: VaccinationMonitoring.list_vaccination_records()
  defp list_records(:unassigned), do: []
  defp list_records(:no_district), do: []

  defp list_records({:locked, district_id}),
    do: VaccinationMonitoring.list_vaccination_records_by_district(district_id)

  defp locked_district({:locked, district_id}, districts),
    do: Enum.find(districts, &(&1.id == district_id))

  defp locked_district(_scope, _districts), do: nil

  defp apply_scope(params, {:locked, district_id}), do: Map.put(params, "district_id", district_id)
  defp apply_scope(params, _scope), do: params

  @impl true
  def handle_event("save", %{"vaccination_record" => params}, socket) do
    case socket.assigns.scope do
      :unassigned ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You need to be assigned to a facility before recording coverage."
         )}

      :no_district ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your facility doesn't have a district set yet - ask an MOH admin to add one."
         )}

      scope ->
        scoped_params = params |> with_reporter(socket) |> apply_scope(scope)

        case VaccinationMonitoring.record_vaccination(scoped_params) do
          {:ok, _record} ->
            {:noreply,
             socket
             |> put_flash(:info, "Vaccination coverage recorded.")
             |> assign_form(VaccinationMonitoring.change_vaccination_record(%VaccinationRecord{}))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end
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
end
