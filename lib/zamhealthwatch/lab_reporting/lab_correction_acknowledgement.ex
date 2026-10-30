defmodule ZamHealthWatch.LabReporting.LabCorrectionAcknowledgement do
  @moduledoc """
  A test's requester marking a correction to its result as seen
  (Iteration 15) - the "the person who ordered the test has been told"
  half of lab regulation's corrected-report rule. Records who and when;
  never updated or deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "lab_correction_acknowledgements" do
    field :correction_id, :binary_id
    field :user_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(acknowledgement, attrs) do
    acknowledgement
    |> cast(attrs, [:correction_id, :user_id])
    |> validate_required([:correction_id, :user_id])
    |> foreign_key_constraint(:correction_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:correction_id, :user_id])
  end
end
