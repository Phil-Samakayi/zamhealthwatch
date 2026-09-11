defmodule ZamHealthWatch.Repo.Migrations.CreateVaccinationRecords do
  use Ecto.Migration

  def change do
    create table(:vaccination_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :antigen, :string, null: false
      add :campaign, :string, null: false
      add :doses_administered, :integer, null: false
      add :target_population, :integer, null: false
      add :district_id, references(:districts, type: :binary_id, on_delete: :restrict), null: false
      add :reported_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:vaccination_records, [:district_id])
    create index(:vaccination_records, [:reported_by_id])
    create index(:vaccination_records, [:antigen])
  end
end
