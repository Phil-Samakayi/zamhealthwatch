defmodule ZamHealthWatch.Repo.Migrations.AddRoleAndFacilityToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string
      add :facility_id, references(:facilities, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:users, [:facility_id])
  end
end
