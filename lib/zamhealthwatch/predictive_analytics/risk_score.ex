defmodule ZamHealthWatch.PredictiveAnalytics.RiskScore do
  @moduledoc """
  A computed (not persisted) outbreak-risk read for one facility - its
  last four weekly case counts, the linear trend across them, and the
  tier that trend maps to.

  Built fresh by `PredictiveAnalytics.list_risk_scores/1` on every call;
  nothing here is ever written to the database, so there's no schema,
  no changeset, no migration - just a plain struct shaped for
  `RiskLive.Index` to render.
  """

  @enforce_keys [:facility_id, :facility_name, :weekly_counts, :recent_count, :trend_slope, :tier]
  defstruct [:facility_id, :facility_name, :weekly_counts, :recent_count, :trend_slope, :tier]

  @type tier :: :insufficient_data | :stable | :elevated

  @type t :: %__MODULE__{
          facility_id: binary(),
          facility_name: String.t(),
          weekly_counts: [non_neg_integer()],
          recent_count: non_neg_integer(),
          trend_slope: float(),
          tier: tier()
        }
end
