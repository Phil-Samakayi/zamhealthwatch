defmodule ZamHealthWatch.PredictiveAnalytics.SupplyAlert do
  @moduledoc """
  A medicine short at a facility that has cases of a disease the
  medicine treats (Iteration 19): ORS below its reorder level at a clinic
  with cholera, say. A shortage of a medicine nobody there needs right
  now is a routine restock and gets no alert.

  `weekly_counts` and `tier` are that disease's four-week trend at that
  facility; `case_count` is the total across the four weeks. Computed by
  `PredictiveAnalytics.list_supply_alerts/1`, never persisted.
  """

  @enforce_keys [
    :facility_id,
    :facility_name,
    :disease,
    :weekly_counts,
    :case_count,
    :tier,
    :medicine,
    :quantity_on_hand,
    :reorder_level
  ]
  defstruct [
    :facility_id,
    :facility_name,
    :disease,
    :weekly_counts,
    :case_count,
    :tier,
    :medicine,
    :quantity_on_hand,
    :reorder_level
  ]

  @type t :: %__MODULE__{
          facility_id: binary(),
          facility_name: String.t(),
          disease: atom(),
          weekly_counts: [non_neg_integer()],
          case_count: pos_integer(),
          tier: ZamHealthWatch.PredictiveAnalytics.RiskScore.tier(),
          medicine: atom(),
          quantity_on_hand: non_neg_integer(),
          reorder_level: non_neg_integer()
        }
end
