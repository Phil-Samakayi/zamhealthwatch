defmodule ZamHealthWatch.CaseManagement.OutcomeCorrection do
  @moduledoc """
  One entry in a case's outcome correction history (Iteration 18).

  Append-only, like `LabReporting.LabResultCorrection`: inserted, never
  updated or deleted, so the record of what was recorded, when it
  changed, why, and by whom stays complete. Two kinds:

    * `:corrected` - the outcome was wrong (recorded as died, but the
      patient was discharged alive, say). `new_outcome` is the right one.
    * `:entered_in_error` - there should be no outcome on this case yet
      (recorded on the wrong case, say). The outcome is removed;
      `new_outcome` stays `nil`.

  A reason of at least 10 characters is required for both.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @outcomes [:recovered, :died]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "case_outcome_corrections" do
    field :kind, Ecto.Enum, values: [:corrected, :entered_in_error]
    field :previous_outcome, Ecto.Enum, values: @outcomes
    field :new_outcome, Ecto.Enum, values: @outcomes
    field :reason, :string
    field :case_id, :binary_id
    field :corrected_by_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  A changeset for recording a correction or removal. The reason is
  trimmed and must be 10 to 1000 characters. `new_outcome` is required
  for `:corrected` and forced to `nil` for `:entered_in_error`.
  """
  def changeset(correction, attrs) do
    correction
    |> cast(attrs, [:kind, :previous_outcome, :new_outcome, :reason, :case_id, :corrected_by_id])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:kind, :previous_outcome, :reason, :case_id, :corrected_by_id])
    |> validate_length(:reason, min: 10, max: 1000)
    |> validate_new_outcome()
    |> foreign_key_constraint(:case_id)
    |> foreign_key_constraint(:corrected_by_id)
  end

  defp validate_new_outcome(changeset) do
    case get_field(changeset, :kind) do
      :corrected -> validate_required(changeset, [:new_outcome])
      :entered_in_error -> put_change(changeset, :new_outcome, nil)
      _other -> changeset
    end
  end
end
