defmodule ZamHealthWatchWeb.EpidemiologyLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Geography

  # Same "each LiveView owns its own display list" precedent as
  # CaseLive.Index's @disease_options - duplicated here rather than
  # shared. Revisit (extract to one place, e.g. a Case.disease_options/0)
  # only once a third consumer needs the same list; two isn't a pattern
  # yet.
  @disease_options [
    {"Cholera", :cholera},
    {"Malaria", :malaria},
    {"Typhoid", :typhoid},
    {"COVID-19", :covid19},
    {"Measles", :measles}
  ]

  @status_options [
    {"Suspected", :suspected},
    {"Confirmed", :confirmed},
    {"Resolved", :resolved}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Epidemiology dashboard
        <:subtitle>
          Live counts across all reported cases. Updates automatically as new cases come in.
        </:subtitle>
      </.header>

      <div class="stats shadow w-full">
        <div class="stat">
          <div class="stat-title">Total cases</div>
          <div class="stat-value">{@total_cases}</div>
        </div>
      </div>

      <div class="divider" />

      <.header>
        By disease
      </.header>

      <div class="stats stats-vertical lg:stats-horizontal shadow w-full">
        <div :for={{label, disease} <- @disease_options} class="stat">
          <div class="stat-title">{label}</div>
          <div class="stat-value text-2xl">{Map.get(@by_disease, disease, 0)}</div>
        </div>
      </div>

      <div class="divider" />

      <.header>
        By status
      </.header>

      <div class="stats stats-vertical lg:stats-horizontal shadow w-full">
        <div :for={{label, status} <- @status_options} class="stat">
          <div class="stat-title">{label}</div>
          <div class="stat-value text-2xl">{Map.get(@by_status, status, 0)}</div>
        </div>
      </div>

      <div class="divider" />

      <.header>
        By facility
        <:subtitle>
          Facilities with at least one reported case, busiest first.
        </:subtitle>
      </.header>

      <p :if={@by_facility == []} id="no-facility-data" class="text-sm text-base-content/60">
        No cases reported yet.
      </p>

      <.table :if={@by_facility != []} id="facility-counts" rows={@by_facility}>
        <:col :let={{name, _count}} label="Facility">{name}</:col>
        <:col :let={{_name, count}} label="Cases">{count}</:col>
      </.table>

      <div class="divider" />

      <.header>
        By district
        <:subtitle>
          Districts with at least one reported case at a facility with a known district, busiest first.
        </:subtitle>
      </.header>

      <p :if={@by_district == []} id="no-district-data" class="text-sm text-base-content/60">
        No cases at a facility with a known district yet.
      </p>

      <.table :if={@by_district != []} id="district-counts" rows={@by_district}>
        <:col :let={{name, _count}} label="District">{name}</:col>
        <:col :let={{_name, count}} label="Cases">{count}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CaseManagement.subscribe_cases()

    socket =
      socket
      |> assign(:disease_options, @disease_options)
      |> assign(:status_options, @status_options)
      |> assign_stats()

    {:ok, socket}
  end

  # Cases are low-volume enough at this iteration (a district-level
  # surveillance tool, not a national firehose) that recomputing every
  # aggregate on any case event is simpler and far less error-prone than
  # tracking incremental deltas per stat - and simple wins until there's
  # an actual performance problem to justify the complexity. Revisit if
  # case volume or update frequency ever makes this measurably slow.
  @impl true
  def handle_info({:created, _case}, socket), do: {:noreply, assign_stats(socket)}
  def handle_info({:updated, _case}, socket), do: {:noreply, assign_stats(socket)}

  defp assign_stats(socket) do
    by_facility_counts = CaseManagement.count_cases_by_facility()
    facilities = Geography.list_facilities()

    by_facility =
      facilities
      |> Enum.flat_map(fn facility ->
        case Map.get(by_facility_counts, facility.id) do
          nil -> []
          count -> [{facility.name, count}]
        end
      end)
      |> Enum.sort_by(fn {_name, count} -> count end, :desc)

    socket
    |> assign(:total_cases, CaseManagement.count_cases())
    |> assign(:by_disease, CaseManagement.count_cases_by_disease())
    |> assign(:by_status, CaseManagement.count_cases_by_status())
    |> assign(:by_facility, by_facility)
    |> assign(:by_district, by_district(facilities, by_facility_counts))
  end

  # Composed here, not in Geography or CaseManagement, same "context
  # stays name/grouping-agnostic, caller composes" split already used
  # for by_facility above: a facility's case count comes from
  # CaseManagement, which district it's in comes from Geography, and
  # neither context needs to know about the other to answer those
  # questions. A facility with no district_id set (still possible -
  # district_id isn't required, same reasoning as latitude/longitude)
  # simply doesn't contribute to any district's total, rather than
  # being folded into a meaningless "unknown district" bucket - the
  # exact trap this aggregate was deferred over in the first place.
  #
  # District names are looked up via a map built from one
  # `list_districts/0` call, not a `get_district!/1` per facility - a
  # facility's `district_id` is also `on_delete: :nothing` at the DB
  # level (per the facilities migration), so a dangling reference is
  # possible in principle; `Map.get/3` just quietly drops it (same as a
  # missing case count above) instead of raising and taking the whole
  # dashboard down with it.
  defp by_district(facilities, by_facility_counts) do
    district_names_by_id = Map.new(Geography.list_districts(), &{&1.id, &1.name})

    facilities
    |> Enum.reduce(%{}, fn facility, totals ->
      case {facility.district_id, Map.get(by_facility_counts, facility.id)} do
        {nil, _count} -> totals
        {_district_id, nil} -> totals
        {district_id, count} -> Map.update(totals, district_id, count, &(&1 + count))
      end
    end)
    |> Enum.flat_map(fn {district_id, count} ->
      case Map.get(district_names_by_id, district_id) do
        nil -> []
        name -> [{name, count}]
      end
    end)
    |> Enum.sort_by(fn {_name, count} -> count end, :desc)
  end
end
