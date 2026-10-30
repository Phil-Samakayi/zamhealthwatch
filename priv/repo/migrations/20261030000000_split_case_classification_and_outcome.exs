defmodule ZamHealthWatch.Repo.Migrations.SplitCaseClassificationAndOutcome do
  use Ecto.Migration

  # Iteration 15: `cases.status` stops meaning two different things.
  # Before this, `resolved` covered both "the patient recovered" and "a
  # negative lab test ruled this out". Afterwards, `status` is only the
  # case's classification (suspected / confirmed / not_a_case), and the
  # new `outcome` column records what happened to the patient.
  #
  # Existing `resolved` rows can be split without guessing, because the
  # two old paths into `resolved` left different evidence behind:
  #
  #   * A negative lab result set `resolved` directly. Those cases have a
  #     resulted lab test whose latest result is negative, so they become
  #     `not_a_case`.
  #   * The case list's "Resolve" button only ever appeared on a
  #     `confirmed` case. Every other `resolved` case was a confirmed case
  #     that someone closed, so it becomes `confirmed` with outcome
  #     `recovered`, dated by the row's last update.
  #
  # `status` is a plain string column (no database-level enum), so the
  # new `not_a_case` value needs no type change.
  def up do
    alter table(:cases) do
      add :outcome, :string
      add :outcome_at, :utc_datetime
    end

    flush()

    execute("""
    UPDATE cases AS c
    SET status = 'not_a_case'
    FROM (
      SELECT DISTINCT ON (case_id) case_id, result
      FROM lab_tests
      WHERE status = 'resulted'
      ORDER BY case_id, resulted_at DESC
    ) AS latest
    WHERE latest.case_id = c.id
      AND c.status = 'resolved'
      AND latest.result = 'negative'
    """)

    execute("""
    UPDATE cases
    SET status = 'confirmed', outcome = 'recovered', outcome_at = updated_at
    WHERE status = 'resolved'
    """)

    create index(:cases, [:outcome])
  end

  # Lossy by necessity: the old schema had one value for both meanings,
  # so anything ruled out or with any outcome folds back into `resolved`.
  def down do
    execute("""
    UPDATE cases
    SET status = 'resolved'
    WHERE status = 'not_a_case' OR outcome IS NOT NULL
    """)

    drop index(:cases, [:outcome])

    alter table(:cases) do
      remove :outcome
      remove :outcome_at
    end
  end
end
