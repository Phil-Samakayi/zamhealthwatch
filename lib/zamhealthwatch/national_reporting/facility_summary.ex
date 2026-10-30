defmodule ZamHealthWatch.NationalReporting.FacilitySummary do
  @moduledoc """
  One row of the national facility-level rollup (see
  `NationalReporting.facility_summary/1`) - every other module's
  current state for a single facility, folded together. Computed fresh
  on every call and never persisted - no schema, no changeset, no
  migration - the same "plain struct built for rendering" shape
  `PredictiveAnalytics.RiskScore` already established for exactly this
  reason (see its own moduledoc).

  `cases_by_status`/`cases_by_outcome`/`lab_tests_by_status` are left as the raw
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
    :cases_by_outcome,
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
    :cases_by_outcome,
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
          cases_by_outcome: %{atom() => non_neg_integer()},
          lab_tests_by_status: %{atom() => non_neg_integer()},
          drug_stock_count: non_neg_integer(),
          drug_shortage_count: non_neg_integer(),
          risk: ZamHealthWatch.PredictiveAnalytics.RiskScore.t() | nil
        }

  @doc """
  The facility's countable case total - suspected plus confirmed, the
  same surveillance counting rule `CaseManagement`'s aggregates use
  (ruled-out reports aren't cases). Kept here so the CSV and the
  on-screen preview can't disagree about what "total" means.
  """
  def case_total(%__MODULE__{cases_by_status: by_status}) do
    Map.get(by_status, :suspected, 0) + Map.get(by_status, :confirmed, 0)
  end
end
