defmodule ZamHealthWatch.Repo.Migrations.CreateCapacityReports do
  use Ecto.Migration

  def change do
    create table(:capacity_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :total_beds, :integer, null: false
      add :occupied_beds, :integer, null: false
      add :icu_beds_total, :integer, null: false
      add :icu_beds_occupied, :integer, null: false
      add :admissions_today, :integer, null: false
      add :facility_id, references(:facilities, type: :binary_id, on_delete: :restrict), null: false
      add :reported_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:capacity_reports, [:facility_id])
    create index(:capacity_reports, [:reported_by_id])
  end
end
