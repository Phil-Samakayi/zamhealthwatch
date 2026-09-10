defmodule ZamHealthWatch.Repo.Migrations.CreateCases do
  use Ecto.Migration

  def change do
    create table(:cases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :disease, :string, null: false
      add :status, :string, null: false, default: "suspected"

      add :facility_id, references(:facilities, type: :binary_id, on_delete: :restrict),
        null: false

      add :reported_by_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cases, [:facility_id])
    create index(:cases, [:reported_by_id])
    create index(:cases, [:disease])
    create index(:cases, [:status])
  end
end
