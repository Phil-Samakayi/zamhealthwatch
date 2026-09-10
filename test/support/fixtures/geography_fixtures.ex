defmodule ZamHealthWatch.GeographyFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ZamHealthWatch.Geography` context.
  """

  @doc """
  Generate a district.
  """
  def district_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "some name",
        province: "some province"
      })

    {:ok, district} = ZamHealthWatch.Geography.create_district(attrs)
    district
  end

  @doc """
  Generate a facility.
  """
  def facility_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "some name"
      })

    {:ok, facility} = ZamHealthWatch.Geography.create_facility(attrs)
    facility
  end
end
