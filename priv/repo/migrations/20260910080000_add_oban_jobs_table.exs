defmodule ZamHealthWatch.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up()

  # We specify `version: 1` in down, ensuring the rollback in earlier
  # migrations will work even if we've migrated to a future version.
  def down, do: Oban.Migration.down(version: 1)
end
