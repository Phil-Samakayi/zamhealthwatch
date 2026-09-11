defmodule ZamHealthWatch.PredictiveAnalytics do
  @moduledoc """
  The PredictiveAnalytics context - the brief's "district-level outbreak
  risk scoring" module, scoped down for this first slice (full reasoning
  in docs/ITERATIONS.md):

    * Scored by *facility*, not district - `Facility.district_id` isn't
      cast anywhere yet, the same gap `EpidemiologyLive.Index` and
      `MapLive.Index` already deferred for the same reason. Nothing to
      group by district on until that's wired.
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

  alias ZamHealthWatch.{CaseManagement, Geography, HospitalCapacity}
  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.PredictiveAnalytics.RiskScore

  @weeks 4
  @rising_threshold 0.5

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
    buckets = weekly_buckets(now)
    capacity_by_facility = HospitalCapacity.latest_capacity_by_facility()

    Geography.list_facilities()
    |> Enum.map(fn facility ->
      counts = Enum.map(buckets, &Map.get(&1, facility.id, 0))
      capacity_report = Map.get(capacity_by_facility, facility.id)
      build_score(facility, counts, capacity_report)
    end)
    |> Enum.sort_by(& &1.recent_count, :desc)
  end

  # `@weeks` consecutive 7-day `%{facility_id => count}` maps ending at
  # `now`, oldest first - e.g. for @weeks = 4, the first bucket covers
  # 4-3 weeks ago and the last covers the most recent 7 days ("this
  # week"). Delegates the actual counting to CaseManagement - this
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
  defp weekly_buckets(now) do
    now = now |> DateTime.truncate(:second) |> DateTime.add(1, :second)

    for weeks_ago <- (@weeks - 1)..0//-1 do
      start_dt = DateTime.add(now, -(weeks_ago + 1) * 7, :day)
      end_dt = DateTime.add(now, -weeks_ago * 7, :day)
      CaseManagement.count_cases_by_facility_between(start_dt, end_dt)
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
