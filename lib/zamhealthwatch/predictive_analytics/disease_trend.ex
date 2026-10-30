defmodule ZamHealthWatch.PredictiveAnalytics.DiseaseTrend do
  @moduledoc """
  One disease's four-week trend within a district (Iteration 17): its
  weekly case counts, the linear slope across them, and the tier that
  slope maps to. Part of a `DistrictRisk`; computed, never persisted.
  """

  @enforce_keys [:disease, :weekly_counts, :recent_count, :trend_slope, :tier]
  defstruct [:disease, :weekly_counts, :recent_count, :trend_slope, :tier]

  @type t :: %__MODULE__{
          disease: atom(),
          weekly_counts: [non_neg_integer()],
          recent_count: non_neg_integer(),
          trend_slope: float(),
          tier: ZamHealthWatch.PredictiveAnalytics.RiskScore.tier()
        }
end
