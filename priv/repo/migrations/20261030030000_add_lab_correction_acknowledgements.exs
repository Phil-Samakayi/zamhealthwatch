defmodule ZamHealthWatch.Repo.Migrations.AddLabCorrectionAcknowledgements do
  use Ecto.Migration

  # Iteration 15, slice 4: lab regulation requires the lab to promptly
  # notify whoever ordered a test when its reported result was wrong.
  # In this app, the notice is shown to the requester on the lab screen
  # until they mark it as seen, and this table records that they did -
  # who, and when. It sits beside the append-only correction history
  # rather than inside it: acknowledging a correction is a separate
  # fact, and the correction rows are never updated.
  #
  # One acknowledgement per user per correction (unique index), so a
  # double click can't record two.
  def change do
    create table(:lab_correction_acknowledgements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :correction_id,
          references(:lab_result_corrections, type: :binary_id, on_delete: :restrict),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:lab_correction_acknowledgements, [:correction_id, :user_id])
    create index(:lab_correction_acknowledgements, [:user_id])
  end
end
