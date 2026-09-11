defmodule ZamHealthWatch.Geography do
  @moduledoc """
  The Geography context.

  Districts and facilities are shared reference data: read by every
  role and written by whichever roles get write access (a policy
  question for later, once Accounts has roles wired up), not owned by
  whichever user happened to create the record. Unlike a per-user
  resource, there is no `user_id`/ownership check here — every request
  sees the same rows.
  """

  import Ecto.Query, warn: false
  alias ZamHealthWatch.Repo

  alias ZamHealthWatch.Geography.District
  alias ZamHealthWatch.Geography.Facility

  @doc """
  Subscribes to notifications about any district changes.

  The broadcasted messages match the pattern:

    * {:created, %District{}}
    * {:updated, %District{}}
    * {:deleted, %District{}}

  """
  def subscribe_districts do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "districts")
  end

  defp broadcast_district(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "districts", message)
  end

  @doc """
  Returns the list of districts.

  ## Examples

      iex> list_districts()
      [%District{}, ...]

  """
  def list_districts do
    Repo.all(District)
  end

  @doc """
  Gets a single district.

  Raises `Ecto.NoResultsError` if the District does not exist.

  ## Examples

      iex> get_district!(123)
      %District{}

      iex> get_district!(456)
      ** (Ecto.NoResultsError)

  """
  def get_district!(id), do: Repo.get!(District, id)

  @doc """
  Creates a district.

  ## Examples

      iex> create_district(%{field: value})
      {:ok, %District{}}

      iex> create_district(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_district(attrs) do
    with {:ok, district = %District{}} <-
           %District{}
           |> District.changeset(attrs)
           |> Repo.insert() do
      broadcast_district({:created, district})
      {:ok, district}
    end
  end

  @doc """
  Updates a district.

  ## Examples

      iex> update_district(district, %{field: new_value})
      {:ok, %District{}}

      iex> update_district(district, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_district(%District{} = district, attrs) do
    with {:ok, district = %District{}} <-
           district
           |> District.changeset(attrs)
           |> Repo.update() do
      broadcast_district({:updated, district})
      {:ok, district}
    end
  end

  @doc """
  Deletes a district.

  ## Examples

      iex> delete_district(district)
      {:ok, %District{}}

      iex> delete_district(district)
      {:error, %Ecto.Changeset{}}

  """
  def delete_district(%District{} = district) do
    with {:ok, district = %District{}} <-
           Repo.delete(district) do
      broadcast_district({:deleted, district})
      {:ok, district}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking district changes.

  ## Examples

      iex> change_district(district)
      %Ecto.Changeset{data: %District{}}

  """
  def change_district(%District{} = district, attrs \\ %{}) do
    District.changeset(district, attrs)
  end

  @doc """
  Subscribes to notifications about any facility changes.

  The broadcasted messages match the pattern:

    * {:created, %Facility{}}
    * {:updated, %Facility{}}
    * {:deleted, %Facility{}}

  """
  def subscribe_facilities do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "facilities")
  end

  defp broadcast_facility(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "facilities", message)
  end

  @doc """
  Returns the list of facilities.

  ## Examples

      iex> list_facilities()
      [%Facility{}, ...]

  """
  def list_facilities do
    Repo.all(Facility)
  end

  @doc """
  Returns the list of facilities that have both a `latitude` and
  `longitude` set.

  Used by `MapLive.Index` - a facility with no known coordinates yet
  (there's no facility-management UI, only seeds/fixtures create them)
  simply doesn't appear on the map rather than plotting at `{0, 0}` or
  erroring. Filtering "has coordinates" lives here (Information Expert:
  `Geography` owns what a facility's location data means), not in the
  LiveView.

  ## Examples

      iex> list_facilities_with_coordinates()
      [%Facility{latitude: -15.4, longitude: 28.3}, ...]

  """
  def list_facilities_with_coordinates do
    Repo.all(
      from f in Facility,
        where: not is_nil(f.latitude) and not is_nil(f.longitude)
    )
  end

  @doc """
  Gets a single facility.

  Raises `Ecto.NoResultsError` if the Facility does not exist.

  ## Examples

      iex> get_facility!(123)
      %Facility{}

      iex> get_facility!(456)
      ** (Ecto.NoResultsError)

  """
  def get_facility!(id), do: Repo.get!(Facility, id)

  @doc """
  Gets a facility by its short `code` (e.g. "UTH"), or `nil` if none matches.

  Used by `SmsReporting` to resolve the facility named in an inbound SMS
  report. Returns `nil` rather than raising - an SMS with a typo'd or
  unknown code is bad input to reject gracefully, not a bug to crash on.

  ## Examples

      iex> get_facility_by_code("UTH")
      %Facility{}

      iex> get_facility_by_code("NOPE")
      nil

  """
  def get_facility_by_code(code) when is_binary(code) do
    Repo.get_by(Facility, code: code)
  end

  @doc """
  Creates a facility.

  ## Examples

      iex> create_facility(%{field: value})
      {:ok, %Facility{}}

      iex> create_facility(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_facility(attrs) do
    with {:ok, facility = %Facility{}} <-
           %Facility{}
           |> Facility.changeset(attrs)
           |> Repo.insert() do
      broadcast_facility({:created, facility})
      {:ok, facility}
    end
  end

  @doc """
  Updates a facility.

  ## Examples

      iex> update_facility(facility, %{field: new_value})
      {:ok, %Facility{}}

      iex> update_facility(facility, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_facility(%Facility{} = facility, attrs) do
    with {:ok, facility = %Facility{}} <-
           facility
           |> Facility.changeset(attrs)
           |> Repo.update() do
      broadcast_facility({:updated, facility})
      {:ok, facility}
    end
  end

  @doc """
  Deletes a facility.

  ## Examples

      iex> delete_facility(facility)
      {:ok, %Facility{}}

      iex> delete_facility(facility)
      {:error, %Ecto.Changeset{}}

  """
  def delete_facility(%Facility{} = facility) do
    with {:ok, facility = %Facility{}} <-
           Repo.delete(facility) do
      broadcast_facility({:deleted, facility})
      {:ok, facility}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking facility changes.

  ## Examples

      iex> change_facility(facility)
      %Ecto.Changeset{data: %Facility{}}

  """
  def change_facility(%Facility{} = facility, attrs \\ %{}) do
    Facility.changeset(facility, attrs)
  end
end
