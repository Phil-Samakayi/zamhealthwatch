defmodule ZamHealthWatch.LabReporting.LabTest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "lab_tests" do
    # `:corrected` and `:entered_in_error` (Iteration 15) follow FHIR's
    # report statuses: a result issued and later fixed, and a result
    # withdrawn because it should never have been recorded. The history
    # behind either is in `LabReporting.LabResultCorrection`.
    field :status, Ecto.Enum,
      values: [:pending, :resulted, :corrected, :entered_in_error],
      default: :pending

    field :result, Ecto.Enum, values: [:positive, :negative, :inconclusive]
    field :resulted_at, :utc_datetime
    field :case_id, :binary_id
    field :requested_by_id, :binary_id
    # Who entered the result (Iteration 15). `nil` on results entered
    # before attribution existed - see the add_resulted_by migration.
    field :resulted_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A lab test changeset for requesting a new test against an existing case.

  `status`/`result`/`resulted_at` are deliberately not castable here - a
  newly requested test always starts `:pending` with no result (the
  schema defaults), the same "one changeset per distinct operation"
  split `CaseManagement.Case` already draws between `changeset/2` and
  `status_changeset/2`. Recording a result is `result_changeset/2`'s job.

  `case_id`/`requested_by_id` are checked against `CaseManagement.Case`
  and `Accounts.User` via `foreign_key_constraint/2` rather than by
  reaching into those schemas directly - the same decoupling every
  other cross-context reference in this project keeps.
  """
  def request_changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:case_id, :requested_by_id])
    |> validate_required([:case_id, :requested_by_id])
    |> foreign_key_constraint(:case_id)
    |> foreign_key_constraint(:requested_by_id)
  end

  @doc """
  A lab test changeset for recording its result.

  Forces `status` to `:resulted` and stamps `resulted_at` as a side
  effect of setting a valid `result` - there's no separate "mark as
  in-progress" state (see `LabReporting`'s module doc for why two
  states, not three, is this slice's cut), so entering a result is the
  only way a test ever leaves `:pending`.

  `resulted_by_id` is required: since Iteration 15 every new result
  records who entered it, the same audit rule `requested_by_id` already
  follows, checked against `Accounts.User` via `foreign_key_constraint/2`.
  """
  def result_changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:result, :resulted_by_id])
    |> validate_required([:result, :resulted_by_id])
    |> foreign_key_constraint(:resulted_by_id)
    |> put_change(:status, :resulted)
    |> put_change(:resulted_at, DateTime.utc_now(:second))
  end

  @doc """
  A lab test changeset for replacing an issued result with a corrected
  one. Sets `status` to `:corrected`. `resulted_at`/`resulted_by_id`
  are left alone on purpose: they still say when and by whom the
  original result was issued, and the correction itself is recorded in
  `LabReporting.LabResultCorrection`.
  """
  def correction_changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:result])
    |> validate_required([:result])
    |> put_change(:status, :corrected)
  end

  @doc """
  A lab test changeset for withdrawing an issued result as entered in
  error. `result` is kept rather than cleared, so the screen can still
  show what was withdrawn - a withdrawn result simply stops counting
  towards the case's classification.
  """
  def withdrawal_changeset(lab_test) do
    change(lab_test, status: :entered_in_error)
  end
end
