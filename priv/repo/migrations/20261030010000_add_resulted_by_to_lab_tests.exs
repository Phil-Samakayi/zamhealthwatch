defmodule ZamHealthWatch.Repo.Migrations.AddResultedByToLabTests do
  use Ecto.Migration

  # Iteration 15, slice 2: record *who* entered a lab result, not just
  # when. `on_delete: :restrict`, the same audit-trail rule
  # `requested_by_id` and `cases.reported_by_id` already follow: a user
  # who has entered results can't be deleted out from under that record.
  #
  # Nullable on purpose. Results entered before this migration have no
  # record of who entered them, and inventing one would be worse than
  # admitting it. New results always set it (see
  # `LabTest.result_changeset/2`).
  def change do
    alter table(:lab_tests) do
      add :resulted_by_id, references(:users, type: :binary_id, on_delete: :restrict)
    end

    create index(:lab_tests, [:resulted_by_id])
  end
end
