defmodule ZamHealthWatchWeb.RiskLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.PredictiveAnalytics

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Outbreak risk
        <:subtitle>
          A trend read on the last four weeks of reported cases per facility. Updates automatically as new cases come in.
        </:subtitle>
      </.header>

      <div class="alert alert-info mt-4">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          This is a statistical trend over case counts already in the system, not a machine-learned prediction - there's no historical dataset loaded yet to train one on.
        </span>
      </div>

      <p :if={@risk_scores == []} id="no-risk-data" class="text-sm text-base-content/60 mt-4">
        No facilities to assess yet.
      </p>

      <.table :if={@risk_scores != []} id="risk-scores" rows={@risk_scores}>
        <:col :let={score} label="Facility">{score.facility_name}</:col>
        <:col :let={score} label="Last 4 weeks">{Enum.join(score.weekly_counts, " → ")}</:col>
        <:col :let={score} label="This week">{score.recent_count}</:col>
        <:col :let={score} label="Trend">{Float.round(score.trend_slope, 2)} cases/week</:col>
        <:col :let={score} label="Risk">
          <span class={["badge", tier_badge_class(score.tier)]}>{tier_label(score.tier)}</span>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CaseManagement.subscribe_cases()

    {:ok, assign_risk_scores(socket)}
  end

  # Same "recompute everything on any case event" call already made for
  # EpidemiologyLive.Index and MapLive.Index - case volume at this
  # iteration doesn't justify incremental tracking, and a new case
  # landing in a different weekly bucket than the last render is
  # exactly the kind of thing a partial update would get wrong anyway.
  @impl true
  def handle_info({:created, _case}, socket), do: {:noreply, assign_risk_scores(socket)}
  def handle_info({:updated, _case}, socket), do: {:noreply, assign_risk_scores(socket)}

  defp assign_risk_scores(socket) do
    assign(socket, :risk_scores, PredictiveAnalytics.list_risk_scores())
  end

  defp tier_label(:elevated), do: "Elevated"
  defp tier_label(:stable), do: "Stable"
  defp tier_label(:insufficient_data), do: "No data"

  defp tier_badge_class(:elevated), do: "badge-error"
  defp tier_badge_class(:stable), do: "badge-success"
  defp tier_badge_class(:insufficient_data), do: "badge-ghost"
end
