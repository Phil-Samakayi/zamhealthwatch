defmodule ZamHealthWatchWeb.RiskLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.PredictiveAnalytics
  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Outbreak risk
        <:subtitle>
          A trend read on the last four weeks of reported cases: per district and disease, then per facility alongside its latest hospital capacity status. Updates automatically as new cases, capacity reports, or vaccination coverage come in.
        </:subtitle>
      </.header>

      <div class="alert alert-info mt-4">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          This is a statistical trend over case counts already in the system, not a machine-learned prediction - there's no historical dataset loaded yet to train one on.
        </span>
      </div>

      <h2 class="text-lg font-semibold mt-6">By district</h2>
      <p class="text-sm text-base-content/60">
        Each disease is trended separately, so a rise in one can't hide behind a fall in another. A district's risk is that of its worst disease. Measles cases in a district whose measles-rubella coverage is below {threshold_percent()}% are raised to High: the population can't stop them spreading. Coverage isn't applied to other diseases, since no vaccine in this system prevents them.
      </p>

      <p
        :if={@district_risks == []}
        id="no-district-risk-data"
        class="text-sm text-base-content/60 mt-4"
      >
        No districts to assess yet.
      </p>

      <.table
        :if={@district_risks != []}
        id="district-risks"
        rows={@district_risks}
        row_id={&"district-#{&1.district_id}"}
      >
        <:col :let={risk} label="District">
          {risk.district_name}
          <span :if={risk.province} class="text-base-content/60">({risk.province})</span>
        </:col>
        <:col :let={risk} label="Risk">
          <span class={["badge", tier_badge_class(risk.tier)]}>{tier_label(risk.tier)}</span>
        </:col>
        <:col :let={risk} label="Cases this week">{risk.recent_count}</:col>
        <:col :let={risk} label="By disease (last 4 weeks)">
          <span :if={risk.diseases == []} class="text-base-content/60">
            No cases in the last 4 weeks
          </span>
          <ul :if={risk.diseases != []} class="space-y-1">
            <li :for={trend <- risk.diseases}>
              <span class="font-medium">{Case.disease_label(trend.disease)}</span>
              {Enum.join(trend.weekly_counts, " → ")}
              <span class={["badge badge-sm", tier_badge_class(trend.tier)]}>
                {tier_label(trend.tier)}
              </span>
              <span :if={trend.escalated_by} class="block text-xs text-base-content/60">
                Cases with {VaccinationRecord.antigen_label(trend.escalated_by.antigen)} coverage at {percent(trend.escalated_by.coverage_rate)}%
              </span>
            </li>
          </ul>
        </:col>
        <:col :let={risk} label="Immunity">
          <div :for={status <- risk.immunity}>
            <span class="text-xs">{VaccinationRecord.antigen_label(status.antigen)}</span>
            <span class={["badge badge-sm", immunity_badge_class(status.status)]}>
              {immunity_label(status)}
            </span>
          </div>
        </:col>
      </.table>

      <h2 class="text-lg font-semibold mt-6">By facility</h2>

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
        <:col :let={score} label="Hospital capacity">
          <span class={["badge", capacity_badge_class(score.capacity_status)]}>
            {capacity_label(score.capacity_status)}
          </span>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      CaseManagement.subscribe_cases()
      HospitalCapacity.subscribe_capacity_reports()
      VaccinationMonitoring.subscribe_vaccination_records()
    end

    {:ok, assign_risk_scores(socket)}
  end

  # Same "recompute everything on any relevant event" call already made
  # for EpidemiologyLive.Index and MapLive.Index - case/capacity volume
  # at this iteration doesn't justify incremental tracking, and a new
  # case landing in a different weekly bucket (or a new capacity report
  # changing which one is "latest") than the last render is exactly the
  # kind of thing a partial update would get wrong anyway. Matched on
  # each event's own struct (`%Case{}`/`%CapacityReport{}`) rather than
  # an unqualified `_case`/`_report`, so it's clear at a glance which
  # topic's broadcast triggered the recompute, now that this LiveView
  # subscribes to two.
  @impl true
  def handle_info({:created, %Case{}}, socket), do: {:noreply, assign_risk_scores(socket)}
  def handle_info({:updated, %Case{}}, socket), do: {:noreply, assign_risk_scores(socket)}
  def handle_info({:created, %CapacityReport{}}, socket), do: {:noreply, assign_risk_scores(socket)}

  def handle_info({:created, %VaccinationRecord{}}, socket),
    do: {:noreply, assign_risk_scores(socket)}

  defp assign_risk_scores(socket) do
    socket
    |> assign(:district_risks, PredictiveAnalytics.list_district_risks())
    |> assign(:risk_scores, PredictiveAnalytics.list_risk_scores())
  end

  defp tier_label(:high), do: "High"
  defp tier_label(:elevated), do: "Elevated"
  defp tier_label(:stable), do: "Stable"
  defp tier_label(:insufficient_data), do: "No data"

  # High is the only red. Elevated drops to amber so the two can be told
  # apart at a glance now that there are three tiers (Iteration 17).
  defp tier_badge_class(:high), do: "badge-error"
  defp tier_badge_class(:elevated), do: "badge-warning"
  defp tier_badge_class(:stable), do: "badge-success"
  defp tier_badge_class(:insufficient_data), do: "badge-ghost"

  # "No reports yet" rather than reusing `tier_label(:insufficient_data)`'s
  # "No data" text - the two badges sit in adjacent columns on the same
  # row and mean different things (no case history vs. no capacity
  # submission), so sharing the exact wording risked reading as one
  # signal instead of two independent ones.
  defp capacity_label(:no_data), do: "No reports yet"
  defp capacity_label(:adequate), do: "Adequate"
  defp capacity_label(:near_capacity), do: "Near capacity"
  defp capacity_label(:over_capacity), do: "Over capacity"

  defp capacity_badge_class(:no_data), do: "badge-ghost"
  defp capacity_badge_class(:adequate), do: "badge-success"
  defp capacity_badge_class(:near_capacity), do: "badge-warning"
  defp capacity_badge_class(:over_capacity), do: "badge-error"

  defp immunity_label(%{status: :no_data}), do: "No coverage data"
  defp immunity_label(%{status: :gap, coverage_rate: rate}), do: "#{percent(rate)}% - gap"
  defp immunity_label(%{status: :adequate, coverage_rate: rate}), do: "#{percent(rate)}%"

  defp immunity_badge_class(:gap), do: "badge-warning"
  defp immunity_badge_class(:adequate), do: "badge-success"
  defp immunity_badge_class(:no_data), do: "badge-ghost"

  defp percent(rate), do: Float.round(rate * 100, 1)

  defp threshold_percent, do: round(PredictiveAnalytics.immunity_threshold() * 100)
end
