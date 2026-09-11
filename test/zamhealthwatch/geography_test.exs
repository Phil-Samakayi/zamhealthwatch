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
      valid_attrs = %{name: "some name", code: "SOME1"}

      assert {:ok, %Facility{} = facility} = Geography.create_facility(valid_attrs)
      assert facility.name == "some name"
      assert facility.code == "SOME1"
    end

    test "create_facility/1 requires a code" do
      assert {:error, changeset} = Geography.create_facility(%{name: "some name"})
      assert %{code: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_facility/1 rejects a lowercase or non-alphanumeric code" do
      assert {:error, changeset} = Geography.create_facility(%{name: "some name", code: "abc"})
      assert %{code: ["must be uppercase letters/numbers only"]} = errors_on(changeset)
    end

    test "get_facility_by_code/1 finds a facility by its code" do
      facility = facility_fixture(%{code: "UTH"})
      assert Geography.get_facility_by_code("UTH") == facility
    end

    test "get_facility_by_code/1 returns nil for an unknown code" do
      assert Geography.get_facility_by_code("NOPE") == nil
    end

    test "create_facility/1 accepts valid coordinates" do
      valid_attrs = %{name: "some name", code: "SOME1", latitude: -15.4, longitude: 28.3}

      assert {:ok, %Facility{} = facility} = Geography.create_facility(valid_attrs)
      assert facility.latitude == -15.4
      assert facility.longitude == 28.3
    end

    test "create_facility/1 rejects an out-of-range latitude" do
      attrs = %{name: "some name", code: "SOME1", latitude: 200.0, longitude: 28.3}

      assert {:error, changeset} = Geography.create_facility(attrs)
      assert %{latitude: ["must be less than or equal to 90"]} = errors_on(changeset)
    end

    test "create_facility/1 rejects an out-of-range longitude" do
      attrs = %{name: "some name", code: "SOME1", latitude: -15.4, longitude: -200.0}

      assert {:error, changeset} = Geography.create_facility(attrs)
      assert %{longitude: ["must be greater than or equal to -180"]} = errors_on(changeset)
    end

    test "create_facility/1 accepts a valid district_id" do
      district = district_fixture()
      attrs = %{name: "some name", code: "SOME1", district_id: district.id}

      assert {:ok, %Facility{} = facility} = Geography.create_facility(attrs)
      assert facility.district_id == district.id
    end

    test "create_facility/1 rejects a district_id that doesn't reference a real district" do
      attrs = %{name: "some name", code: "SOME1", district_id: Ecto.UUID.generate()}

      assert {:error, changeset} = Geography.create_facility(attrs)
      assert %{district_id: ["does not exist"]} = errors_on(changeset)
    end

    test "create_facility/1 without a district_id leaves it nil" do
      assert {:ok, %Facility{} = facility} =
               Geography.create_facility(%{name: "some name", code: "SOME1"})

      assert facility.district_id == nil
    end

    test "list_facilities_with_coordinates/0 only returns facilities with both lat and lng" do
      with_coords = facility_fixture(%{code: "WC1", latitude: -15.4, longitude: 28.3})
      _without_coords = facility_fixture(%{code: "NC1"})

      assert Geography.list_facilities_with_coordinates() == [with_coords]
    end

    test "list_facilities_with_coordinates/0 returns an empty list when none have coordinates" do
      facility_fixture(%{code: "NC2"})
      assert Geography.list_facilities_with_coordinates() == []
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
