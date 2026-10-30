defmodule ZamHealthWatch.PredictiveAnalytics.DistrictRisk do
  @moduledoc """
  A computed (not persisted) outbreak-risk read for one district
  (Iteration 17): a `DiseaseTrend` for each disease with cases in the
  last four weeks, worst first, the district's overall tier, which is
  its worst disease's tier, and an `ImmunityStatus` for each
  vaccine-preventable disease, whether or not it has cases.

  Built fresh by `PredictiveAnalytics.list_district_risks/1` on every
  call, the same way `RiskScore` is for facilities.
  """

  alias ZamHealthWatch.PredictiveAnalytics.{DiseaseTrend, ImmunityStatus}

  @enforce_keys [
    :district_id,
    :district_name,
    :province,
    :recent_count,
    :tier,
    :diseases,
    :immunity
  ]
  defstruct [
    :district_id,
    :district_name,
    :province,
    :recent_count,
    :tier,
    :diseases,
    :immunity
  ]

  @type t :: %__MODULE__{
          district_id: binary(),
          district_name: String.t(),
          province: String.t() | nil,
          recent_count: non_neg_integer(),
          tier: ZamHealthWatch.PredictiveAnalytics.RiskScore.tier(),
          diseases: [DiseaseTrend.t()],
          immunity: [ImmunityStatus.t()]
        }
end
