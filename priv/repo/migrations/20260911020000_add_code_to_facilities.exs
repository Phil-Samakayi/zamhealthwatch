defmodule ZamHealthWatch.Repo.Migrations.AddCodeToFacilities do
  use Ecto.Migration

  def change do
    alter table(:facilities) do
      add :code, :string
    end

    create unique_index(:facilities, [:code])
  end
end
