defmodule ZamHealthWatch.PredictiveAnalytics.DistrictRisk do
  @moduledoc """
  A computed (not persisted) outbreak-risk read for one district
  (Iteration 17): a `DiseaseTrend` for each disease with cases in the
  last four weeks, worst first, and the district's overall tier, which
  is its worst disease's tier.

  Built fresh by `PredictiveAnalytics.list_district_risks/1` on every
  call, the same way `RiskScore` is for facilities.
  """

  alias ZamHealthWatch.PredictiveAnalytics.DiseaseTrend

  @enforce_keys [:district_id, :district_name, :province, :recent_count, :tier, :diseases]
  defstruct [:district_id, :district_name, :province, :recent_count, :tier, :diseases]

  @type t :: %__MODULE__{
          district_id: binary(),
          district_name: String.t(),
          province: String.t() | nil,
          recent_count: non_neg_integer(),
          tier: ZamHealthWatch.PredictiveAnalytics.RiskScore.tier(),
          diseases: [DiseaseTrend.t()]
        }
end
