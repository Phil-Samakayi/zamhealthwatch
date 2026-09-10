defmodule ZamHealthWatch.Repo.Migrations.CreateFacilities do
  use Ecto.Migration

  def change do
    create table(:facilities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :district_id, references(:districts, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:facilities, [:district_id])
  end
end
