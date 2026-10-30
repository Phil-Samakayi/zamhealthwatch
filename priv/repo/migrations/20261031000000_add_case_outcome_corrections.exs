defmodule ZamHealthWatch.Repo.Migrations.AddCaseOutcomeCorrections do
  use Ecto.Migration

  # Iteration 18: correcting a recorded outcome, the same way Iteration
  # 15 corrects a lab result.
  #
  # 1. `cases.outcome_recorded_by_id` - who recorded the outcome. Until
  #    now only the recorder's *role* was checked and nobody was stored,
  #    so a correction history couldn't say whose entry it corrected.
  #    Nullable: outcomes recorded before this migration have no known
  #    recorder, and a case with no outcome has none either.
  #
  # 2. `case_outcome_corrections` - an append-only history. Every change
  #    or removal of a recorded outcome adds a row with the previous
  #    outcome, the new one (nil when removed as entered in error), a
  #    required reason, who did it, and when. Never updated or deleted:
  #    no `updated_at`, and every foreign key is `:restrict`.
  def change do
    alter table(:cases) do
      add :outcome_recorded_by_id, references(:users, type: :binary_id, on_delete: :restrict)
    end

    create table(:case_outcome_corrections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :case_id, references(:cases, type: :binary_id, on_delete: :restrict), null: false
      add :kind, :string, null: false
      add :previous_outcome, :string, null: false
      add :new_outcome, :string
      add :reason, :text, null: false

      add :corrected_by_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      # Microsecond precision, as for lab result corrections: the
      # history's order is the audit trail.
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:case_outcome_corrections, [:case_id])
    create index(:case_outcome_corrections, [:corrected_by_id])
  end
end
