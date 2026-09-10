defmodule ZamHealthWatch.GeographyTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.Geography

  describe "districts" do
    alias ZamHealthWatch.Geography.District

    import ZamHealthWatch.GeographyFixtures

    @invalid_attrs %{name: nil, province: nil}

    test "list_districts/0 returns all districts" do
      district = district_fixture()
      assert Geography.list_districts() == [district]
    end

    test "get_district!/1 returns the district with given id" do
      district = district_fixture()
      assert Geography.get_district!(district.id) == district
    end

    test "create_district/1 with valid data creates a district" do
      valid_attrs = %{name: "some name", province: "some province"}

      assert {:ok, %District{} = district} = Geography.create_district(valid_attrs)
      assert district.name == "some name"
      assert district.province == "some province"
    end

    test "create_district/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Geography.create_district(@invalid_attrs)
    end

    test "update_district/2 with valid data updates the district" do
      district = district_fixture()
      update_attrs = %{name: "some updated name", province: "some updated province"}

      assert {:ok, %District{} = district} = Geography.update_district(district, update_attrs)
      assert district.name == "some updated name"
      assert district.province == "some updated province"
    end

    test "update_district/2 with invalid data returns error changeset" do
      district = district_fixture()
      assert {:error, %Ecto.Changeset{}} = Geography.update_district(district, @invalid_attrs)
      assert district == Geography.get_district!(district.id)
    end

    test "delete_district/1 deletes the district" do
      district = district_fixture()
      assert {:ok, %District{}} = Geography.delete_district(district)
      assert_raise Ecto.NoResultsError, fn -> Geography.get_district!(district.id) end
    end

    test "change_district/1 returns a district changeset" do
      district = district_fixture()
      assert %Ecto.Changeset{} = Geography.change_district(district)
    end
  end

  describe "facilities" do
    alias ZamHealthWatch.Geography.Facility

    import ZamHealthWatch.GeographyFixtures

    @invalid_attrs %{name: nil}

    test "list_facilities/0 returns all facilities" do
      facility = facility_fixture()
      assert Geography.list_facilities() == [facility]
    end

    test "get_facility!/1 returns the facility with given id" do
      facility = facility_fixture()
      assert Geography.get_facility!(facility.id) == facility
    end

    test "create_facility/1 with valid data creates a facility" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %Facility{} = facility} = Geography.create_facility(valid_attrs)
      assert facility.name == "some name"
    end

    test "create_facility/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Geography.create_facility(@invalid_attrs)
    end

    test "update_facility/2 with valid data updates the facility" do
      facility = facility_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Facility{} = facility} = Geography.update_facility(facility, update_attrs)
      assert facility.name == "some updated name"
    end

    test "update_facility/2 with invalid data returns error changeset" do
      facility = facility_fixture()
      assert {:error, %Ecto.Changeset{}} = Geography.update_facility(facility, @invalid_attrs)
      assert facility == Geography.get_facility!(facility.id)
    end

    test "delete_facility/1 deletes the facility" do
      facility = facility_fixture()
      assert {:ok, %Facility{}} = Geography.delete_facility(facility)
      assert_raise Ecto.NoResultsError, fn -> Geography.get_facility!(facility.id) end
    end

    test "change_facility/1 returns a facility changeset" do
      facility = facility_fixture()
      assert %Ecto.Changeset{} = Geography.change_facility(facility)
    end
  end
end
