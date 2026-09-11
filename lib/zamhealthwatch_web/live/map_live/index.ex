defmodule ZamHealthWatchWeb.MapLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Geography

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Case map
        <:subtitle>
          Facilities with a known location, sized by reported case count. Updates live as new cases come in.
        </:subtitle>
      </.header>

      <p :if={@facility_count == 0} id="no-mapped-facilities" class="text-sm text-base-content/60">
        No facilities have a known location yet.
      </p>

      <div
        :if={@facility_count > 0}
        id="case-map"
        phx-hook=".Map"
        phx-update="ignore"
        class="w-full h-[32rem] rounded-box border border-base-300"
      >
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Map">
        export default {
          mounted() {
            this.map = L.map(this.el)

            L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
              attribution: "&copy; OpenStreetMap contributors",
              maxZoom: 19
            }).addTo(this.map)

            // Fallback view roughly centered on Zambia - overridden by
            // fitBounds() below as soon as there's at least one marker.
            this.map.setView([-14.5, 28.0], 6)

            this.markers = L.layerGroup().addTo(this.map)

            this.handleEvent("map:update", ({facilities}) => this.renderFacilities(facilities))
          },

          renderFacilities(facilities) {
            this.markers.clearLayers()

            const points = []

            facilities.forEach((facility) => {
              const radius = 6 + Math.min(facility.case_count, 20) * 2
              const label = facility.case_count === 1 ? "case" : "cases"

              L.circleMarker([facility.lat, facility.lng], {
                radius,
                color: "#dc2626",
                fillColor: "#dc2626",
                fillOpacity: 0.5
              })
                .bindPopup(`<strong>${facility.name}</strong><br/>${facility.case_count} ${label}`)
                .addTo(this.markers)

              points.push([facility.lat, facility.lng])
            })

            if (points.length > 0) {
              this.map.fitBounds(points, {padding: [30, 30], maxZoom: 12})
            }
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CaseManagement.subscribe_cases()

    {:ok, assign_map_data(socket)}
  end

  # Same "recompute everything on any case event" simplicity as
  # EpidemiologyLive.Index - case volume at this iteration doesn't
  # justify tracking incremental per-marker deltas, and it reuses
  # CaseManagement.count_cases_by_facility/0 already built for the
  # dashboard rather than duplicating aggregation logic.
  @impl true
  def handle_info({:created, _case}, socket), do: {:noreply, assign_map_data(socket)}
  def handle_info({:updated, _case}, socket), do: {:noreply, assign_map_data(socket)}

  defp assign_map_data(socket) do
    facilities = Geography.list_facilities_with_coordinates()
    counts_by_facility = CaseManagement.count_cases_by_facility()

    socket = assign(socket, :facility_count, length(facilities))

    if connected?(socket) do
      points =
        Enum.map(facilities, fn facility ->
          %{
            id: facility.id,
            name: facility.name,
            lat: facility.latitude,
            lng: facility.longitude,
            case_count: Map.get(counts_by_facility, facility.id, 0)
          }
        end)

      push_event(socket, "map:update", %{facilities: points})
    else
      socket
    end
  end
end
