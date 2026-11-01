defmodule ZamHealthWatch.NationalReporting do
  @moduledoc """
  The NationalReporting context - the brief's "aggregated, exportable
  reporting for MOH-level consumption - the rollup of everything else"
  module, and deliberately the last of the twelve to get built: every
  other module's public API already existed by the time this one
  started, so this context's entire job is to call them and shape what
  comes back into one MOH-facing snapshot. No new schema, no new table,
  nothing persisted here.

  Scoped down for this first slice (full reasoning in docs/ITERATIONS.md):

    * **CSV only**, not PDF/Excel - the brief says "exportable", not
      which format, and CSV is what a MOH analyst actually pastes
      straight into Excel/Stata/R for further work, with zero new
      dependency this project doesn't already have a real need for
      (see `to_csv/1` below - a minimal RFC 4180 writer, not a library).
    * **A current snapshot, not a selectable date range** - no module
      in this project exposes an as-of/historical query yet
      (`PredictiveAnalytics`'s weekly trend buckets aside, and those
      aren't a general date-range primitive), so a date-range selector
      here would be a UI control with nothing underneath it to actually
      filter by historically. Logged as the natural next slice once a
      module exists that needs one.
    * **Facility-level rollup, not one row per case/test/record** -
      "aggregated" is the brief's own word, and a row per individual
      case/test/stock entry is what the Epidemiology Dashboard and each
      module's own screen already give a closer look at. One row per
      facility, every other module's current state folded into that
      row, is the shape that actually earns the word "rollup".
    * **Vaccination coverage stays a second, district-grain table in
      the same CSV, not folded into the per-facility rows** -
      `VaccinationRecord` is genuinely district-grain (see
      `VaccinationMonitoring`'s own moduledoc - no `facility_id` column
      exists on it at all), so repeating a district's coverage figure
      on every facility row in that district would overstate a
      precision this data doesn't have. A second table, stacked under
      the first with a blank line between them, keeps both grains in
      one file honestly rather than inventing a facility-level figure
      that doesn't exist.

  Depends on every other context's existing public API only
  (`CaseManagement`, `LabReporting`, `VaccinationMonitoring`,
  `DrugAvailability`, `PredictiveAnalytics`, `Geography`) - High
  Cohesion/Low Coupling, the same direction every other cross-context
  dependency in this project already runs: this context knows about all
  of them, none of them know this context exists.
  `PredictiveAnalytics.list_risk_scores/1` already folds in
  `HospitalCapacity`'s latest-per-facility status onto each `RiskScore`
  (see its own moduledoc), so this context reads hospital capacity
  through that existing integration rather than re-deriving it a
  second way.
  """

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.NationalReporting.FacilitySummary
  alias ZamHealthWatch.PredictiveAnalytics
  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @facility_headers [
    "Facility",
    "District",
    "Cases (suspected)",
    "Cases (confirmed)",
    "Cases (total)",
    "Ruled out (not a case)",
    "Deaths",
    "Lab tests (pending)",
    "Lab tests (resulted)",
    "Drug stock records",
    "Drug stock shortages",
    "Hospital capacity status",
    "Risk tier",
    "Case trend (4wk slope)"
  ]

  @vaccination_headers [
    "District",
    "Antigen",
    "Campaign",
    "Doses administered",
    "Target population",
    "Coverage"
  ]

  @doc """
  Returns one `FacilitySummary` per known facility, same facility order
  `Geography.list_facilities/0` returns - the facility-level half of
  the national rollup, and the same read both `NationalReportingLive.Index`
  (for on-screen preview) and `export_csv/1` (for the download) build
  on, computed once here rather than twice.

  Takes `now` as an explicit argument (defaulting to the current time),
  same reason `PredictiveAnalytics.list_risk_scores/1` already does -
  it's threaded straight through to that function so a test can pin
  down exactly which case counts land in which weekly bucket.

  ## Examples

      iex> facility_summary()
      [%FacilitySummary{}, ...]

  """
  def facility_summary(now \\ DateTime.utc_now()) do
    districts_by_id = Geography.list_districts() |> Map.new(&{&1.id, &1.name})
    risk_by_facility = now |> PredictiveAnalytics.list_risk_scores() |> Map.new(&{&1.facility_id, &1})

    Geography.list_facilities()
    |> Enum.map(&build_facility_summary(&1, districts_by_id, risk_by_facility))
  end

  defp build_facility_summary(facility, districts_by_id, risk_by_facility) do
    cases = CaseManagement.list_cases_by_facility(facility.id)
    cases_by_status = Enum.frequencies_by(cases, & &1.status)

    # Outcomes among countable cases only - a ruled-out report has no
    # outcome to count (CaseManagement.record_outcome/3 refuses one).
    cases_by_outcome =
      cases
      |> Enum.filter(&(&1.status != :not_a_case and not is_nil(&1.outcome)))
      |> Enum.frequencies_by(& &1.outcome)

    lab_tests_by_status =
      facility.id
      |> LabReporting.list_lab_tests_by_facility()
      |> Enum.frequencies_by(& &1.status)

    # Newest first, so `uniq_by/2` keeps each medicine's latest count.
    # Shortages are counted on those only (Iteration 20): before, every
    # record ever submitted counted, so a medicine since restocked still
    # showed as short.
    drug_stocks = DrugAvailability.list_drug_stocks_by_facility(facility.id)
    current_stock = Enum.uniq_by(drug_stocks, & &1.medicine)

    %FacilitySummary{
      facility_id: facility.id,
      facility_name: facility.name,
      district_name: Map.get(districts_by_id, facility.district_id, "-"),
      cases_by_status: cases_by_status,
      cases_by_outcome: cases_by_outcome,
      lab_tests_by_status: lab_tests_by_status,
      drug_stock_count: length(drug_stocks),
      drug_shortage_count: Enum.count(current_stock, &DrugStock.shortage?/1),
      risk: Map.get(risk_by_facility, facility.id)
    }
  end

  @doc """
  Builds the current national snapshot as CSV, returned as iodata
  (ready for `Plug.Conn.send_resp/3`, or `IO.iodata_to_binary/1` in a
  test) - the facility rollup table from `facility_summary/1`, a blank
  line, then the district-grain vaccination coverage table (see this
  module's own moduledoc for why they're two tables, not one).

  ## Examples

      iex> export_csv() |> IO.iodata_to_binary()
      "Facility,District,...\\r\\n..."

  """
  def export_csv(now \\ DateTime.utc_now()) do
    facility_rows = Enum.map(facility_summary(now), &facility_csv_row/1)
    vaccination_rows = Enum.map(vaccination_coverage(), &vaccination_csv_row/1)

    [
      to_csv([@facility_headers | facility_rows]),
      "\r\n",
      to_csv([@vaccination_headers | vaccination_rows])
    ]
  end

  defp facility_csv_row(%FacilitySummary{} = summary) do
    [
      summary.facility_name,
      summary.district_name,
      Map.get(summary.cases_by_status, :suspected, 0),
      Map.get(summary.cases_by_status, :confirmed, 0),
      FacilitySummary.case_total(summary),
      Map.get(summary.cases_by_status, :not_a_case, 0),
      Map.get(summary.cases_by_outcome, :died, 0),
      Map.get(summary.lab_tests_by_status, :pending, 0),
      FacilitySummary.issued_lab_results(summary),
      summary.drug_stock_count,
      summary.drug_shortage_count,
      risk_label(summary.risk, :capacity_status),
      risk_label(summary.risk, :tier),
      trend_slope_label(summary.risk)
    ]
  end

  # `risk` is `nil` only if a facility somehow isn't in
  # `PredictiveAnalytics.list_risk_scores/1`'s own result - it scores
  # every known facility itself, so this is defensive rather than a
  # state this module's own tests expect to hit (same "absence isn't a
  # guessed default" reasoning as everywhere else, not a real gap).
  defp risk_label(nil, _key), do: "no data"
  defp risk_label(risk, key), do: risk |> Map.fetch!(key) |> Phoenix.Naming.humanize()

  defp trend_slope_label(nil), do: "-"
  defp trend_slope_label(%{trend_slope: slope}), do: slope |> Float.round(2) |> to_string()

  @doc """
  Returns every vaccination record alongside its district's name, as
  `{VaccinationRecord, district_name}` pairs - the district-grain half
  of the rollup, shared by `export_csv/1`'s second table and
  `NationalReportingLive.Index`'s on-screen preview of it. A plain
  pass-through over `VaccinationMonitoring.list_vaccination_records/0`
  (no new context function needed there) composed with
  `Geography.list_districts/0` in memory, the same "caller joins names
  itself" split `VaccinationLive.Index` already follows for its own
  table.

  ## Examples

      iex> vaccination_coverage()
      [{%VaccinationRecord{}, "Lusaka"}, ...]

  """
  def vaccination_coverage do
    districts_by_id = Geography.list_districts() |> Map.new(&{&1.id, &1.name})

    VaccinationMonitoring.list_vaccination_records()
    |> Enum.map(&{&1, Map.get(districts_by_id, &1.district_id, "-")})
  end

  defp vaccination_csv_row({%VaccinationRecord{} = record, district_name}) do
    [
      district_name,
      VaccinationRecord.antigen_label(record.antigen),
      record.campaign,
      record.doses_administered,
      record.target_population,
      "#{record |> VaccinationRecord.coverage_rate() |> Kernel.*(100) |> Float.round(1)}%"
    ]
  end

  # Minimal RFC 4180 CSV writer - no new dependency (e.g. NimbleCSV)
  # added for what's otherwise a handful of lines: a field is wrapped in
  # double quotes (with any embedded quote doubled) only when it
  # actually contains a comma, quote, or newline, the usual "don't force
  # quoting where it isn't needed" convention. `\r\n` line endings, per
  # the RFC, for maximum "opens cleanly in Excel" compatibility - the
  # actual target reader for a MOH analyst's CSV export.
  defp to_csv(rows) do
    Enum.map_join(rows, "", fn row -> Enum.map_join(row, ",", &csv_field/1) <> "\r\n" end)
  end

  defp csv_field(nil), do: ""

  defp csv_field(value) do
    string = to_string(value)

    if String.contains?(string, [",", "\"", "\n"]) do
      "\"" <> String.replace(string, "\"", "\"\"") <> "\""
    else
      string
    end
  end
end
