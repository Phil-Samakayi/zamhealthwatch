defmodule ZamHealthWatch.NationalReporting.FacilitySummary do
  @moduledoc """
  One row of the national facility-level rollup (see
  `NationalReporting.facility_summary/1`) - every other module's
  current state for a single facility, folded together. Computed fresh
  on every call and never persisted - no schema, no changeset, no
  migration - the same "plain struct built for rendering" shape
  `PredictiveAnalytics.RiskScore` already established for exactly this
  reason (see its own moduledoc).

  `cases_by_status`/`lab_tests_by_status` are left as the raw
  `%{status_atom => count}` maps `Enum.frequencies_by/2` produces,
  not already zero-filled or humanized - same "caller composes a
  display format, this doesn't guess at one" division of labour
  `CaseManagement.count_cases_by_disease/0` already draws. `risk` is
  the whole `PredictiveAnalytics.RiskScore` struct (or `nil`, for the
  same "absence isn't a guessed default" reason `HospitalCapacity`'s
  own `:no_data` status exists) rather than pulled apart into separate
  fields here - callers that only want `risk.tier` or
  `risk.capacity_status` can reach for those themselves.
  """

  @enforce_keys [
    :facility_id,
    :facility_name,
    :district_name,
    :cases_by_status,
    :lab_tests_by_status,
    :drug_stock_count,
    :drug_shortage_count,
    :risk
  ]
  defstruct [
    :facility_id,
    :facility_name,
    :district_name,
    :cases_by_status,
    :lab_tests_by_status,
    :drug_stock_count,
    :drug_shortage_count,
    :risk
  ]

  @type t :: %__MODULE__{
          facility_id: binary(),
          facility_name: String.t(),
          district_name: String.t(),
          cases_by_status: %{atom() => non_neg_integer()},
          lab_tests_by_status: %{atom() => non_neg_integer()},
          drug_stock_count: non_neg_integer(),
          drug_shortage_count: non_neg_integer(),
          risk: ZamHealthWatch.PredictiveAnalytics.RiskScore.t() | nil
        }
end
