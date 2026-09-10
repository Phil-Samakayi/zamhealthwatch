defmodule ZamHealthWatch.Repo.Migrations.CreateDistricts do
  use Ecto.Migration

  def change do
    create table(:districts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :province, :string

      timestamps(type: :utc_datetime)
    end
  end
end
