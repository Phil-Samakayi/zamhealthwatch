defmodule ZamHealthWatch.LabReporting.LabTest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "lab_tests" do
    field :status, Ecto.Enum, values: [:pending, :resulted], default: :pending
    field :result, Ecto.Enum, values: [:positive, :negative, :inconclusive]
    field :resulted_at, :utc_datetime
    field :case_id, :binary_id
    field :requested_by_id, :binary_id

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
  """
  def result_changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:result])
    |> validate_required([:result])
    |> put_change(:status, :resulted)
    |> put_change(:resulted_at, DateTime.utc_now(:second))
  end
end
