defmodule ZamHealthWatch.PredictiveAnalytics do
  @moduledoc """
  The PredictiveAnalytics context - the brief's "district-level outbreak
  risk scoring" module. Two reads, both computed fresh on every call:

    * `list_district_risks/1` (Iteration 17) - the district-level read
      the brief asks for. Each disease is trended separately within a
      district, and the district takes its worst disease's tier. Real
      surveillance thresholds (Zambia's IDSR, ZNPHI's district alert
      thresholds) are per disease and per district, and adding diseases
      together lets a rise in one hide behind a fall in another: cholera
      going 1, 2, 3, 4 while malaria goes 4, 3, 2, 1 sums to a flat
      5, 5, 5, 5.

      Vaccination coverage feeds in here, but only for the disease the
      vaccine prevents: measles cases in a district whose latest
      measles-rubella coverage is below 95% raise measles, and so the
      district, to `:high`. See `@vaccine_for` below.
    * `list_supply_alerts/1` (Iteration 19) - medicine shortages at
      facilities that have cases of a disease the medicine treats. See
      `@medicines_for` below.
    * `list_risk_scores/1` - the original per-facility read, all
      diseases together, with the facility's hospital capacity status
      beside it. Kept because capacity is reported per facility and a
      district officer still needs to see which clinic is under strain.

  How both are calculated (full reasoning in docs/ITERATIONS.md):

    * A linear trend over the last four weeks of *case counts already
      in this system*, not a trained ML model - there's no historical
      WHO/MOH dataset loaded anywhere to train one on (the brief's own
      Section 6.2 flags this as a real limitation, not something this
      slice can route around). This is real arithmetic over real data
      via Nx, not a placeholder - just a statistical heuristic, not a
      classifier.

  Deliberately its own context rather than folded into `CaseManagement`,
  even though every input comes from there - interpreting case counts
  as a *risk* is a distinct responsibility from owning and counting
  cases (Information Expert: `CaseManagement` answers "how many cases",
  this context answers "is that trending up"), the same split the brief
  draws between Disease Surveillance and Predictive Analytics as
  separate modules. `CaseManagement` and `Geography` stay unaware this
  context exists, same decoupling as everywhere else in this project.

  As of the Hospital Capacity integration, `list_risk_scores/1` also
  attaches each facility's latest `HospitalCapacity.CapacityReport.capacity_status/1`
  onto its `RiskScore` (see `RiskScore.capacity_status`) - `HospitalCapacity`
  shares this context's per-facility grain (unlike `VaccinationMonitoring`'s
  district-level one), so the lookup is a straightforward join in memory.
  Deliberately **not** blended into `tier` itself: deciding how bed
  strain should combine with a case-count trend into one number is a
  real judgment call with no real use case behind it yet, so both
  signals are surfaced side by side on `RiskLive.Index` rather than
  merged into a formula this project would otherwise be guessing at.
  `HospitalCapacity` still stays unaware this context exists - the
  dependency runs one direction only, same as `CaseManagement`/
  `Geography` above.
  """

  alias ZamHealthWatch.{
    CaseManagement,
    DrugAvailability,
    Geography,
    HospitalCapacity,
    VaccinationMonitoring
  }

  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.HospitalCapacity.CapacityReport

  alias ZamHealthWatch.PredictiveAnalytics.{
    DiseaseTrend,
    DistrictRisk,
    ImmunityStatus,
    RiskScore,
    SupplyAlert
  }

  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @weeks 4
  @rising_threshold 0.5

  # Higher is worse. Picks a district's tier from its diseases' tiers,
  # and sorts districts and diseases most at risk first.
  @tier_rank %{insufficient_data: 0, stable: 1, elevated: 2, high: 3}

  # Which vaccine protects against which disease this system tracks.
  # Of the five diseases cases can be reported for, only measles has an
  # antigen in VaccinationRecord's list - there's none for cholera,
  # malaria, typhoid, or COVID-19 - so coverage is applied to measles
  # and nothing else. Coverage of one vaccine says nothing about a
  # disease it doesn't prevent.
  @vaccine_for %{measles: :measles_rubella}

  # Coverage below this leaves an immunity gap. 95% is the commonly
  # cited level needed to stop measles spreading, and population
  # immunity is one of the four categories in WHO's district-level
  # measles risk assessment tool. The tool's other three (surveillance
  # quality, programme performance, threat assessment) need data this
  # system doesn't collect.
  @immunity_threshold 0.95

  @doc "The coverage rate below which a district has an immunity gap, as a fraction."
  def immunity_threshold, do: @immunity_threshold

  # Which tracked medicines treat which disease (Iteration 19), limited
  # to the five medicines DrugStock records:
  #
  #   * Cholera: rehydration is the treatment - ORS for mild or moderate
  #     dehydration, IV Ringer's lactate for severe. Antibiotics are only
  #     for severe cases, and the first-line ones (doxycycline,
  #     azithromycin) aren't tracked. Ciprofloxacin is left out on
  #     purpose: reduced susceptibility makes it a poor cholera choice.
  #   * Malaria: artemether-lumefantrine, first-line for uncomplicated
  #     malaria.
  #   * Typhoid: ciprofloxacin and ceftriaxone, both among WHO's
  #     recommended options, with local resistance deciding between them.
  #
  # Measles and COVID-19 have no tracked medicine, so they never raise a
  # supply alert. Adding a medicine to DrugStock and a pair here is all
  # it takes to extend this.
  @medicines_for %{
    cholera: [:ors, :iv_fluids],
    malaria: [:al],
    typhoid: [:ciprofloxacin, :ceftriaxone]
  }

  @doc "The tracked medicines that treat `disease`, or `[]`."
  def medicines_for(disease), do: Map.get(@medicines_for, disease, [])

  @doc """
  Returns one `RiskScore` per known facility, highest recent case count
  first.

  Takes `now` as an explicit argument (defaulting to the current time)
  rather than always calling `DateTime.utc_now/0` internally, so a test
  can pin down exactly which cases fall in which of the four weekly
  windows instead of racing the wall clock.

  ## Examples

      iex> list_risk_scores()
      [%RiskScore{}, ...]

  """
  def list_risk_scores(now \\ DateTime.utc_now()) do
    buckets =
      now
      |> weekly_windows()
      |> Enum.map(fn {start_dt, end_dt} ->
        CaseManagement.count_cases_by_facility_between(start_dt, end_dt)
      end)

    capacity_by_facility = HospitalCapacity.latest_capacity_by_facility()

    Geography.list_facilities()
    |> Enum.map(fn facility ->
      counts = Enum.map(buckets, &Map.get(&1, facility.id, 0))
      capacity_report = Map.get(capacity_by_facility, facility.id)
      build_score(facility, counts, capacity_report)
    end)
    |> Enum.sort_by(& &1.recent_count, :desc)
  end

  @doc """
  Returns one `DistrictRisk` per district, most at risk first.

  Within each district, every disease with at least one case in the
  last four weeks gets its own `DiseaseTrend` (weekly counts, slope,
  tier), worst first. The district's tier is its worst disease's tier,
  or `:insufficient_data` when it had no cases at all. A facility with
  no district isn't counted in any district; it still appears in
  `list_risk_scores/1`.

  Vaccination: each district also gets an `ImmunityStatus` for every
  vaccine-preventable disease (only measles, today), from its latest
  coverage record. If that's an immunity gap and the disease has cases
  in the window, the disease's tier is raised to `:high`. A gap with no
  cases is shown but changes no tier: it's a vulnerability, not an
  outbreak. No coverage record is `:no_data` and changes nothing.

  Same `now` argument as `list_risk_scores/1`, for the same reason.
  """
  def list_district_risks(now \\ DateTime.utc_now()) do
    district_by_facility =
      Geography.list_facilities()
      |> Enum.reject(&is_nil(&1.district_id))
      |> Map.new(&{&1.id, &1.district_id})

    buckets =
      now
      |> facility_disease_buckets()
      |> Enum.map(&by_district_and_disease(&1, district_by_facility))

    coverage_by_disease =
      Map.new(@vaccine_for, fn {disease, antigen} ->
        {disease, VaccinationMonitoring.latest_coverage_by_district(antigen)}
      end)

    Geography.list_districts()
    |> Enum.map(&build_district_risk(&1, buckets, coverage_by_disease))
    |> Enum.sort_by(&{-Map.fetch!(@tier_rank, &1.tier), -&1.recent_count, &1.district_name})
  end

  @doc """
  Returns a `SupplyAlert` for every medicine below its reorder level at
  a facility that had cases of a disease it treats in the last four
  weeks, worst trend first.

  Stock is each facility's latest submission per medicine, so a
  shortage that has since been restocked no longer alerts. A facility
  with no stock record for a medicine raises nothing: an unreported
  stock isn't assumed to be short.

  Same `now` argument as `list_risk_scores/1`, for the same reason.
  """
  def list_supply_alerts(now \\ DateTime.utc_now()) do
    buckets = facility_disease_buckets(now)
    stock = DrugAvailability.latest_stock_by_facility_and_medicine()
    facility_names = Map.new(Geography.list_facilities(), &{&1.id, &1.name})

    buckets
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn {facility_id, disease} = key ->
      counts = Enum.map(buckets, &Map.get(&1, key, 0))

      for medicine <- medicines_for(disease),
          %DrugStock{} = record <- [Map.get(stock, {facility_id, medicine})],
          DrugStock.shortage?(record) do
        %SupplyAlert{
          facility_id: facility_id,
          facility_name: Map.get(facility_names, facility_id, "Unknown facility"),
          disease: disease,
          weekly_counts: counts,
          case_count: Enum.sum(counts),
          tier: tier_for(counts, trend_slope(counts)),
          medicine: medicine,
          quantity_on_hand: record.quantity_on_hand,
          reorder_level: record.reorder_level
        }
      end
    end)
    |> Enum.sort_by(
      &{-Map.fetch!(@tier_rank, &1.tier), -&1.case_count, &1.facility_name, &1.medicine}
    )
  end

  # The four weekly `%{{facility_id, disease} => count}` maps, oldest
  # first, that both the district read and supply alerts build on.
  defp facility_disease_buckets(now) do
    now
    |> weekly_windows()
    |> Enum.map(fn {start_dt, end_dt} ->
      CaseManagement.count_cases_by_facility_and_disease_between(start_dt, end_dt)
    end)
  end

  # Folds `%{{facility_id, disease} => count}` into
  # `%{{district_id, disease} => count}`, dropping facilities with no
  # district.
  defp by_district_and_disease(counts, district_by_facility) do
    Enum.reduce(counts, %{}, fn {{facility_id, disease}, count}, acc ->
      case Map.fetch(district_by_facility, facility_id) do
        {:ok, district_id} -> Map.update(acc, {district_id, disease}, count, &(&1 + count))
        :error -> acc
      end
    end)
  end

  defp build_district_risk(district, buckets, coverage_by_disease) do
    immunity =
      @vaccine_for
      |> Enum.sort()
      |> Enum.map(fn {disease, antigen} ->
        record = coverage_by_disease |> Map.fetch!(disease) |> Map.get(district.id)
        immunity_status(disease, antigen, record)
      end)

    diseases =
      buckets
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.filter(fn {district_id, _disease} -> district_id == district.id end)
      |> Enum.map(fn {_district_id, disease} -> disease end)
      |> Enum.uniq()
      |> Enum.map(fn disease ->
        counts = Enum.map(buckets, &Map.get(&1, {district.id, disease}, 0))
        build_disease_trend(disease, counts, immunity)
      end)
      |> Enum.sort_by(
        &{-Map.fetch!(@tier_rank, &1.tier), -&1.recent_count, -&1.trend_slope, &1.disease}
      )

    %DistrictRisk{
      district_id: district.id,
      district_name: district.name,
      province: district.province,
      recent_count: diseases |> Enum.map(& &1.recent_count) |> Enum.sum(),
      tier: worst_tier(diseases),
      diseases: diseases,
      immunity: immunity
    }
  end

  defp immunity_status(disease, antigen, nil) do
    %ImmunityStatus{disease: disease, antigen: antigen, coverage_rate: nil, status: :no_data}
  end

  defp immunity_status(disease, antigen, %VaccinationRecord{} = record) do
    rate = VaccinationRecord.coverage_rate(record)
    status = if rate < @immunity_threshold, do: :gap, else: :adequate
    %ImmunityStatus{disease: disease, antigen: antigen, coverage_rate: rate, status: status}
  end

  # `diseases` is already sorted worst first. Every disease in it had at
  # least one case in the window, so none is :insufficient_data - only a
  # district with no diseases at all is.
  defp worst_tier([]), do: :insufficient_data
  defp worst_tier([worst | _rest]), do: worst.tier

  # Every disease reaching here had at least one case in the window, so
  # a gap for it means cases are already circulating in a population
  # that can't stop them spreading - :high whatever the slope says.
  defp build_disease_trend(disease, counts, immunity) do
    slope = trend_slope(counts)
    gap = Enum.find(immunity, &(&1.disease == disease and &1.status == :gap))

    %DiseaseTrend{
      disease: disease,
      weekly_counts: counts,
      recent_count: List.last(counts),
      trend_slope: slope,
      tier: if(gap, do: :high, else: tier_for(counts, slope)),
      escalated_by: gap
    }
  end

  # `@weeks` consecutive 7-day `{start, end}` windows ending at `now`,
  # oldest first - e.g. for @weeks = 4, the first covers 4-3 weeks ago
  # and the last covers the most recent 7 days ("this week"). Each read
  # above asks CaseManagement to count inside these windows - this
  # context only ever asks it "how many, in this window".
  #
  # `now` is padded forward to the next whole second before any bucket
  # math happens. The most recent bucket's end boundary is `now` itself,
  # compared with a strict "<" (count_cases_by_facility_between/2's
  # half-open [start, end) window) - and `Case.inserted_at` is a
  # `:utc_datetime` column, second precision, not microsecond. A case
  # reported and then immediately re-queried by this exact function (as
  # RiskLive.Index does off the very next `{:created, _}` broadcast) can
  # truncate to the *same* second as `now`, and "same" fails a strict
  # "less than" - silently dropping a just-reported case from its own
  # "this week" bucket. A full second of padding closes that race
  # without touching count_cases_by_facility_between/2's semantics.
  defp weekly_windows(now) do
    now = now |> DateTime.truncate(:second) |> DateTime.add(1, :second)

    for weeks_ago <- (@weeks - 1)..0//-1 do
      {DateTime.add(now, -(weeks_ago + 1) * 7, :day), DateTime.add(now, -weeks_ago * 7, :day)}
    end
  end

  defp build_score(facility, counts, capacity_report) do
    slope = trend_slope(counts)

    %RiskScore{
      facility_id: facility.id,
      facility_name: facility.name,
      weekly_counts: counts,
      recent_count: List.last(counts),
      trend_slope: slope,
      tier: tier_for(counts, slope),
      capacity_status: capacity_status_for(capacity_report)
    }
  end

  # `nil` (no capacity report ever submitted for this facility) reads
  # as `:no_data`, distinct from any of `CapacityReport.capacity_status/1`'s
  # own values - same "absence isn't a guessed default" reasoning
  # `HospitalCapacity.latest_capacity_by_facility/0` already applies at
  # the query layer.
  defp capacity_status_for(nil), do: :no_data
  defp capacity_status_for(%CapacityReport{} = report), do: CapacityReport.capacity_status(report)

  # Least-squares slope of weekly case counts against week index
  # (0, 1, 2, ...) via Nx - the brief's "attempt Elixir-native first"
  # call for this module. Kept to Nx's small, long-stable numeric core
  # (tensor/1, mean/1, subtract/2, multiply/2, pow/2, sum/1, divide/2,
  # to_number/1) rather than anything backend-specific, since this
  # session can't check Nx's exact current API against live docs (no
  # hex.pm route) - if `mix test`/compilation fails on something
  # Nx-shaped, this function is the first place to look, same flag this
  # project already raised for Broadway and Oban when they were new.
  defp trend_slope(counts) do
    x = Nx.tensor(Enum.to_list(0..(length(counts) - 1)), type: {:f, 32})
    y = Nx.tensor(counts, type: {:f, 32})

    x_centered = Nx.subtract(x, Nx.mean(x))
    y_centered = Nx.subtract(y, Nx.mean(y))

    numerator = x_centered |> Nx.multiply(y_centered) |> Nx.sum()
    denominator = x_centered |> Nx.pow(2) |> Nx.sum()

    numerator |> Nx.divide(denominator) |> Nx.to_number()
  end

  # A facility with zero cases across the whole four-week window isn't
  # "stable" - there's nothing to judge a trend from, and saying so
  # plainly beats a misleadingly confident 0.0 slope. Otherwise: an
  # average rise of at least `@rising_threshold` cases/week over the
  # window reads as an elevated trend worth a human looking at;
  # anything flatter or falling reads as stable. Two tiers, not three -
  # there's no real case-volume data yet at this project's dev/demo
  # scale to calibrate a second ("critical") threshold against, and a
  # fabricated one would be worse than not having it. Revisit once real
  # usage gives real numbers to tune against.
  defp tier_for(counts, slope) do
    cond do
      Enum.all?(counts, &(&1 == 0)) -> :insufficient_data
      slope >= @rising_threshold -> :elevated
      true -> :stable
    end
  end
end
