defmodule ZamHealthWatchWeb.NationalReportingLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.LabReporting.LabTest
  alias ZamHealthWatch.NationalReporting
  alias ZamHealthWatch.NationalReporting.FacilitySummary
  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        National reporting
        <:subtitle>
          The current snapshot across every module, rolled up for MOH-level consumption -
          one row per facility below, plus district-level vaccination coverage further
          down. Updates automatically as new reports come in; the download is the same
          snapshot as a CSV file.
        </:subtitle>
        <:actions>
          <.button href={~p"/reports/national.csv"} download>Download CSV</.button>
        </:actions>
      </.header>

      <.header>
        Facility rollup
      </.header>

      <p
        :if={@facility_summaries == []}
        id="no-facility-summaries"
        class="text-sm text-base-content/60"
      >
        No facilities to report on yet.
      </p>

      <.table :if={@facility_summaries != []} id="facility-summaries" rows={@facility_summaries}>
        <:col :let={s} label="Facility">{s.facility_name}</:col>
        <:col :let={s} label="District">{s.district_name}</:col>
        <:col :let={s} label="Cases">{case_counts_label(s)}</:col>
        <:col :let={s} label="Deaths">{Map.get(s.cases_by_outcome, :died, 0)}</:col>
        <:col :let={s} label="Lab tests">{lab_test_counts_label(s.lab_tests_by_status)}</:col>
        <:col :let={s} label="Drug stock">{drug_stock_label(s)}</:col>
        <:col :let={s} label="Hospital capacity">
          <span class={["badge", capacity_badge_class(s.risk)]}>{capacity_label(s.risk)}</span>
        </:col>
        <:col :let={s} label="Risk">
          <span class={["badge", tier_badge_class(s.risk)]}>{tier_label(s.risk)}</span>
        </:col>
      </.table>

      <div class="divider" />

      <.header>
        Vaccination coverage by district
        <:subtitle>
          Reported at district level, not facility level - see the Vaccination Monitoring
          module for why.
        </:subtitle>
      </.header>

      <p
        :if={@vaccination_rows == []}
        id="no-vaccination-rows"
        class="text-sm text-base-content/60"
      >
        No vaccination coverage recorded yet.
      </p>

      <.table :if={@vaccination_rows != []} id="vaccination-coverage" rows={@vaccination_rows}>
        <:col :let={{_record, district_name}} label="District">{district_name}</:col>
        <:col :let={{record, _district_name}} label="Antigen">
          {VaccinationRecord.antigen_label(record.antigen)}
        </:col>
        <:col :let={{record, _district_name}} label="Campaign">{record.campaign}</:col>
        <:col :let={{record, _district_name}} label="Coverage">
          <span class={["badge", coverage_badge_class(record)]}>{coverage_percent(record)}%</span>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      CaseManagement.subscribe_cases()
      LabReporting.subscribe_lab_tests()
      VaccinationMonitoring.subscribe_vaccination_records()
      DrugAvailability.subscribe_drug_stocks()
      HospitalCapacity.subscribe_capacity_reports()
    end

    {:ok, assign_snapshot(socket)}
  end

  # Same "recompute everything on any relevant event" call
  # EpidemiologyLive.Index/MapLive.Index/RiskLive.Index already make -
  # this screen is the rollup of *all five* of those contexts' topics,
  # so it subscribes to every one of them and recomputes the whole
  # snapshot on any of their broadcasts rather than tracking each
  # module's contribution incrementally. Matched on each event's own
  # struct, same reason RiskLive.Index's handle_info clauses are, so
  # it's clear at a glance which topic triggered the recompute.
  @impl true
  def handle_info({:created, %Case{}}, socket), do: {:noreply, assign_snapshot(socket)}
  def handle_info({:updated, %Case{}}, socket), do: {:noreply, assign_snapshot(socket)}
  def handle_info({:created, %LabTest{}}, socket), do: {:noreply, assign_snapshot(socket)}
  def handle_info({:updated, %LabTest{}}, socket), do: {:noreply, assign_snapshot(socket)}
  def handle_info({:created, %VaccinationRecord{}}, socket), do: {:noreply, assign_snapshot(socket)}
  def handle_info({:created, %DrugStock{}}, socket), do: {:noreply, assign_snapshot(socket)}
  def handle_info({:created, %CapacityReport{}}, socket), do: {:noreply, assign_snapshot(socket)}

  defp assign_snapshot(socket) do
    socket
    |> assign(:facility_summaries, NationalReporting.facility_summary())
    |> assign(:vaccination_rows, NationalReporting.vaccination_coverage())
  end

  defp case_counts_label(%FacilitySummary{cases_by_status: by_status} = summary) do
    "#{FacilitySummary.case_total(summary)} " <>
      "(#{Map.get(by_status, :suspected, 0)} suspected · " <>
      "#{Map.get(by_status, :confirmed, 0)} confirmed) · " <>
      "#{Map.get(by_status, :not_a_case, 0)} ruled out"
  end

  defp lab_test_counts_label(lab_tests_by_status) do
    "#{Map.get(lab_tests_by_status, :pending, 0)} pending · " <>
      "#{Map.get(lab_tests_by_status, :resulted, 0)} resulted"
  end

  defp drug_stock_label(%{drug_stock_count: count, drug_shortage_count: shortages}) do
    "#{count} record#{if count != 1, do: "s"}, #{shortages} shortage#{if shortages != 1, do: "s"}"
  end

  # Same tier/capacity label-and-badge pairs RiskLive.Index already
  # establishes (see its own comments for the full reasoning), taking
  # the whole `RiskScore` (or `nil`) rather than a bare atom - this
  # screen's `FacilitySummary.risk` can be `nil` in principle (see
  # `NationalReporting.build_facility_summary/3`'s own defensive note),
  # which RiskLive.Index's `risk_scores` list itself never contains.
  defp tier_label(nil), do: "No data"
  defp tier_label(%{tier: :elevated}), do: "Elevated"
  defp tier_label(%{tier: :stable}), do: "Stable"
  defp tier_label(%{tier: :insufficient_data}), do: "No data"

  defp tier_badge_class(nil), do: "badge-ghost"
  defp tier_badge_class(%{tier: :elevated}), do: "badge-error"
  defp tier_badge_class(%{tier: :stable}), do: "badge-success"
  defp tier_badge_class(%{tier: :insufficient_data}), do: "badge-ghost"

  defp capacity_label(nil), do: "No reports yet"
  defp capacity_label(%{capacity_status: :no_data}), do: "No reports yet"
  defp capacity_label(%{capacity_status: :adequate}), do: "Adequate"
  defp capacity_label(%{capacity_status: :near_capacity}), do: "Near capacity"
  defp capacity_label(%{capacity_status: :over_capacity}), do: "Over capacity"

  defp capacity_badge_class(nil), do: "badge-ghost"
  defp capacity_badge_class(%{capacity_status: :no_data}), do: "badge-ghost"
  defp capacity_badge_class(%{capacity_status: :adequate}), do: "badge-success"
  defp capacity_badge_class(%{capacity_status: :near_capacity}), do: "badge-warning"
  defp capacity_badge_class(%{capacity_status: :over_capacity}), do: "badge-error"

  # Same 80%/50% placeholder thresholds VaccinationLive.Index's own
  # coverage_badge_class/1 already uses (see its own comment) -
  # duplicated here rather than shared, same per-module convention
  # every LiveView in this project follows.
  defp coverage_badge_class(record) do
    rate = VaccinationRecord.coverage_rate(record)

    cond do
      rate >= 0.8 -> "badge-success"
      rate >= 0.5 -> "badge-warning"
      true -> "badge-error"
    end
  end

  defp coverage_percent(record) do
    record |> VaccinationRecord.coverage_rate() |> Kernel.*(100) |> Float.round(1)
  end
end
