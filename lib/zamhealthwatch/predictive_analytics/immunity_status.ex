defmodule ZamHealthWatch.PredictiveAnalytics.ImmunityStatus do
  @moduledoc """
  A district's vaccination coverage for one vaccine-preventable disease
  (Iteration 17): the antigen that protects against it, the latest
  coverage rate, and whether that leaves an immunity gap.

  `status` is `:gap` below `PredictiveAnalytics.immunity_threshold/0`,
  `:adequate` at or above it, and `:no_data` when the district has no
  coverage record for the antigen - unknown, not assumed safe or unsafe.
  Part of a `DistrictRisk`; computed, never persisted.
  """

  @enforce_keys [:disease, :antigen, :coverage_rate, :status]
  defstruct [:disease, :antigen, :coverage_rate, :status]

  @type status :: :gap | :adequate | :no_data

  @type t :: %__MODULE__{
          disease: atom(),
          antigen: atom(),
          coverage_rate: float() | nil,
          status: status()
        }
end
