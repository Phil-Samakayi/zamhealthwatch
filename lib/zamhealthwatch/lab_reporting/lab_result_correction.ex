defmodule ZamHealthWatch.LabReporting.LabResultCorrection do
  @moduledoc """
  One entry in a lab test's correction history (Iteration 15).

  Append-only: a correction is inserted and never updated or deleted.
  Fixing a mistaken correction is another correction, so the record of
  what was believed, when, and why stays complete. The two kinds follow
  FHIR's report statuses:

    * `:corrected` - the result itself was wrong (a contaminated sample
      retested negative, say). `new_result` is the right one.
    * `:entered_in_error` - the result should never have been recorded
      against this test (entered on the wrong patient's case, say). The
      result is withdrawn; `new_result` stays `nil`.

  A reason is required for both. "Corrected" with no explanation is
  exactly the kind of record an audit can't make sense of later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @results [:positive, :negative, :inconclusive]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "lab_result_corrections" do
    field :kind, Ecto.Enum, values: [:corrected, :entered_in_error]
    field :previous_result, Ecto.Enum, values: @results
    field :new_result, Ecto.Enum, values: @results
    field :reason, :string
    field :lab_test_id, :binary_id
    field :corrected_by_id, :binary_id

    # Microsecond precision - see the migration: history order must be
    # unambiguous even for corrections made in the same second.
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  A changeset for recording a correction or withdrawal.

  The reason is trimmed and must be at least 10 characters - long enough
  that "typo" or "wrong" won't pass, short of demanding an essay.
  `new_result` is required for `:corrected` and must be empty for
  `:entered_in_error`.
  """
  def changeset(correction, attrs) do
    correction
    |> cast(attrs, [:kind, :previous_result, :new_result, :reason, :lab_test_id, :corrected_by_id])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:kind, :previous_result, :reason, :lab_test_id, :corrected_by_id])
    |> validate_length(:reason, min: 10, max: 1000)
    |> validate_new_result()
    |> foreign_key_constraint(:lab_test_id)
    |> foreign_key_constraint(:corrected_by_id)
  end

  defp validate_new_result(changeset) do
    case get_field(changeset, :kind) do
      :corrected -> validate_required(changeset, [:new_result])
      :entered_in_error -> put_change(changeset, :new_result, nil)
      _other -> changeset
    end
  end
end
