defmodule ZamHealthWatch.Repo.Migrations.AddCoordinatesToFacilities do
  use Ecto.Migration

  @moduledoc """
  Plain `float` `latitude`/`longitude`, not a PostGIS `geography(Point)`
  column - see docs/ITERATIONS.md, Iteration 2's GIS Mapping decisions,
  for why this slice deliberately doesn't adopt `geo_postgis` yet. Both
  are nullable: a facility without known coordinates yet should still
  be creatable, it just won't appear on the map (`MapLive.Index` only
  plots facilities that have both).
  """

  def change do
    alter table(:facilities) do
      add :latitude, :float
      add :longitude, :float
    end
  end
end
