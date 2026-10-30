defmodule ZamHealthWatch.PredictiveAnalytics.DiseaseTrend do
  @moduledoc """
  One disease's four-week trend within a district (Iteration 17): its
  weekly case counts, the linear slope across them, and its tier. Part
  of a `DistrictRisk`; computed, never persisted.

  `tier` is normally what the slope maps to. When the district has an
  immunity gap for this disease, it's `:high` instead, and
  `escalated_by` holds the `ImmunityStatus` that caused it, so the
  screen can say why.
  """

  alias ZamHealthWatch.PredictiveAnalytics.ImmunityStatus

  @enforce_keys [:disease, :weekly_counts, :recent_count, :trend_slope, :tier]
  defstruct [:disease, :weekly_counts, :recent_count, :trend_slope, :tier, escalated_by: nil]

  @type t :: %__MODULE__{
          disease: atom(),
          weekly_counts: [non_neg_integer()],
          recent_count: non_neg_integer(),
          trend_slope: float(),
          tier: ZamHealthWatch.PredictiveAnalytics.RiskScore.tier(),
          escalated_by: ImmunityStatus.t() | nil
        }
end
