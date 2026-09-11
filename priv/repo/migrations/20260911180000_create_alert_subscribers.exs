defmodule ZamHealthWatch.Repo.Migrations.CreateAlertSubscribers do
  use Ecto.Migration

  def change do
    create table(:alert_subscribers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phone, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:alert_subscribers, [:phone])
  end
end
