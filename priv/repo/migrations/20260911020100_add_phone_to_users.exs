defmodule ZamHealthWatch.Repo.Migrations.AddPhoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone, :string
    end

    create unique_index(:users, [:phone])
  end
end
