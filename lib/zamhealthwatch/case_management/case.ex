defmodule ZamHealthWatch.CaseManagement.Case do
  use Ecto.Schema
  import Ecto.Changeset

  @disease_options [
    {"Cholera", :cholera},
    {"Malaria", :malaria},
    {"Typhoid", :typhoid},
    {"COVID-19", :covid19},
    {"Measles", :measles}
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cases" do
    field :disease, Ecto.Enum, values: [:cholera, :malaria, :typhoid, :covid19, :measles]

    # The case's *classification* - how certain it is that this is a real
    # case of `disease` - in the sense surveillance systems use "case
    # status" (IDSR, SORMAS, CDC's NNDSS). Deliberately separate from
    # `outcome` below since Iteration 15: before that, `:resolved` meant
    # both "recovered" and "ruled out by a negative lab test", and the two
    # are opposite things for surveillance - one is a real case, the
    # other was never a case at all. See docs/ITERATIONS.md.
    field :status, Ecto.Enum,
      values: [:suspected, :confirmed, :not_a_case],
      default: :suspected

    # What happened to the patient, independent of classification. `nil`
    # until recorded. A suspected case can have an outcome too - a
    # patient can die before a lab result comes back.
    field :outcome, Ecto.Enum, values: [:recovered, :died]
    field :outcome_at, :utc_datetime

    # Who recorded `outcome` (Iteration 18), so a correction history can
    # say whose entry it corrected. `nil` with no outcome, and for
    # outcomes recorded before this was stored.
    field :outcome_recorded_by_id, :binary_id

    # When a person confirmed this case on clinical or epidemiological
    # grounds (the case list's Confirm button), or `nil` if nobody has.
    # Kept as its own fact since Iteration 15 so that `status` can be
    # recalculated from lab results without losing it - see
    # `CaseManagement.classification_for/2`.
    field :clinically_confirmed_at, :utc_datetime

    field :facility_id, :binary_id
    field :reported_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A case changeset for reporting a new case (or editing its core details).

  `status` and `outcome` are deliberately not castable here - a new case
  always starts `:suspected` with no outcome (the schema defaults).
  Changing classification is `status_changeset/2`'s job and recording an
  outcome is `outcome_changeset/2`'s, so a single "edit case" form can't
  accidentally change either.

  `facility_id` and `reported_by_id` are checked against `Geography.Facility`
  and `Accounts.User` via `foreign_key_constraint/2` rather than by reaching
  into those schemas directly, keeping contexts decoupled.
  """
  def changeset(case, attrs) do
    case
    |> cast(attrs, [:disease, :facility_id, :reported_by_id])
    |> validate_required([:disease, :facility_id, :reported_by_id])
    |> foreign_key_constraint(:facility_id)
    |> foreign_key_constraint(:reported_by_id)
  end

  @doc """
  A case changeset for changing its classification (`:suspected`,
  `:confirmed`, or `:not_a_case`).

  Only checks that `status` is one of the valid values, not that the
  transition is legal - which transitions a *person* may make by hand is
  `CaseManagement.advance_case_status/2`'s rule, and a lab result can
  legitimately move a case in any direction (a positive result on a
  case previously ruled out confirms it again).
  """
  def status_changeset(case, attrs) do
    case
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end

  @doc """
  A case changeset for a person confirming the case clinically: records
  when, and sets the classification to `:confirmed`.
  """
  def clinical_confirmation_changeset(case) do
    change(case,
      status: :confirmed,
      clinically_confirmed_at: DateTime.utc_now(:second)
    )
  end

  @doc """
  A case changeset for recording the patient's outcome. Stamps
  `outcome_at` alongside it, the same "set as a side effect of the real
  change" shape `LabTest.result_changeset/2` uses for `resulted_at`.
  """
  def outcome_changeset(case, attrs) do
    case
    |> cast(attrs, [:outcome, :outcome_recorded_by_id])
    |> validate_required([:outcome])
    |> put_change(:outcome_at, DateTime.utc_now(:second))
    |> foreign_key_constraint(:outcome_recorded_by_id)
  end

  @doc """
  A case changeset for correcting a recorded outcome to `new_outcome`
  (Iteration 18). Keeps `outcome_at` and `outcome_recorded_by_id`: the
  original entry's time and author stay as they were, and the correction
  itself is recorded in `CaseManagement.OutcomeCorrection`.
  """
  def outcome_correction_changeset(case, new_outcome) do
    case
    |> cast(%{outcome: new_outcome}, [:outcome])
    |> validate_required([:outcome])
  end

  @doc """
  A case changeset for removing an outcome recorded in error (Iteration
  18): the case goes back to having no outcome, so one can be recorded
  afresh.
  """
  def outcome_withdrawal_changeset(case) do
    change(case, outcome: nil, outcome_at: nil, outcome_recorded_by_id: nil)
  end

  @doc """
  Returns the `{label, value}` options list for every valid `disease`
  value, in display order - the single source of truth `disease_label/1`
  and every disease-picking `<select>` in this project (`CaseLive.Index`'s
  report form, `EpidemiologyLive.Index`'s by-disease stat tiles,
  `LabLive.Index`'s lab-test-to-case picker) now share, instead of each
  LiveView keeping its own copy. Extracted here - not into
  `CaseManagement` itself - because this is exactly the kind of thing
  Information Expert says belongs with the schema that declares the
  valid values in the first place, not the context around it. Pulled out
  once a third consumer needed the same list; two wasn't yet a pattern
  worth generalizing (see Iteration 2's GIS Mapping decision log, which
  first flagged this duplication and deliberately left it alone).

  ## Examples

      iex> disease_options()
      [{"Cholera", :cholera}, ...]

  """
  def disease_options, do: @disease_options

  @doc """
  Returns a human-readable label for a `disease` value (e.g. `:covid19`
  -> `"COVID-19"`), looked up in `disease_options/0` rather than derived
  with `Phoenix.Naming.humanize/1` - humanize's underscore-to-space,
  one-capital-letter rule can't produce "COVID-19" from `:covid19`.

  ## Examples

      iex> disease_label(:covid19)
      "COVID-19"

  """
  def disease_label(disease) do
    Enum.find_value(@disease_options, Phoenix.Naming.humanize(disease), fn {label, value} ->
      value == disease && label
    end)
  end
end
