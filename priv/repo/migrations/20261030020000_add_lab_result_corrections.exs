defmodule ZamHealthWatch.Repo.Migrations.AddLabResultCorrections do
  use Ecto.Migration

  # Iteration 15, slice 3: lab result corrections, done the way lab
  # regulation and FHIR describe them.
  #
  # 1. `lab_result_corrections` - an append-only history. Every
  #    correction or withdrawal of an issued result adds a row recording
  #    the previous result, the new one, a required reason, who did it,
  #    and when. Rows are never updated or deleted (no `updated_at`
  #    column, and every foreign key is `:restrict`), so the original
  #    result is always recoverable from the earliest correction's
  #    `previous_result` - US lab regulation's "keep both the original
  #    and the corrected report".
  #
  # 2. `cases.clinically_confirmed_at` - a health worker confirming a
  #    case on clinical or epidemiological grounds is now its own
  #    recorded fact, not just a status value. From this slice on, a
  #    case's classification is recalculated from its lab results
  #    whenever one changes. Without this column, withdrawing a positive
  #    result on a case someone had also confirmed clinically would
  #    wrongly drop it back to "suspected".
  #
  #    Backfill: a case that's confirmed today without any positive lab
  #    result behind it can only have been confirmed by hand, so it gets
  #    `clinically_confirmed_at = updated_at`. That includes cases the
  #    previous slice's migration turned from "resolved" into "confirmed,
  #    recovered" - every "resolved" case without a negative result had
  #    been confirmed by hand first.
  def up do
    create table(:lab_result_corrections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :lab_test_id, references(:lab_tests, type: :binary_id, on_delete: :restrict),
        null: false

      add :kind, :string, null: false
      add :previous_result, :string, null: false
      add :new_result, :string
      add :reason, :text, null: false

      add :corrected_by_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      # Microsecond precision: the history's order *is* the audit trail,
      # and two corrections made within the same second would otherwise
      # sort ambiguously.
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:lab_result_corrections, [:lab_test_id])
    create index(:lab_result_corrections, [:corrected_by_id])

    alter table(:cases) do
      add :clinically_confirmed_at, :utc_datetime
    end

    flush()

    execute("""
    UPDATE cases
    SET clinically_confirmed_at = updated_at
    WHERE status = 'confirmed'
      AND NOT EXISTS (
        SELECT 1 FROM lab_tests t
        WHERE t.case_id = cases.id
          AND t.status = 'resulted'
          AND t.result = 'positive'
      )
    """)
  end

  def down do
    alter table(:cases) do
      remove :clinically_confirmed_at
    end

    drop table(:lab_result_corrections)
  end
end
