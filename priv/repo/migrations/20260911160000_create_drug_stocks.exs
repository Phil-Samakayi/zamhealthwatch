defmodule ZamHealthWatch.Repo.Migrations.CreateDrugStocks do
  use Ecto.Migration

  def change do
    create table(:drug_stocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :medicine, :string, null: false
      add :quantity_on_hand, :integer, null: false
      add :reorder_level, :integer, null: false
      add :facility_id, references(:facilities, type: :binary_id, on_delete: :restrict), null: false
      add :reported_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:drug_stocks, [:facility_id])
    create index(:drug_stocks, [:reported_by_id])
    create index(:drug_stocks, [:medicine])
  end
end
