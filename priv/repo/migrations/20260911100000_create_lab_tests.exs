defmodule ZamHealthWatch.Repo.Migrations.CreateLabTests do
  use Ecto.Migration

  def change do
    create table(:lab_tests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :result, :string
      add :resulted_at, :utc_datetime

      add :case_id, references(:cases, type: :binary_id, on_delete: :restrict), null: false

      add :requested_by_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lab_tests, [:case_id])
    create index(:lab_tests, [:requested_by_id])
    create index(:lab_tests, [:status])
  end
end
