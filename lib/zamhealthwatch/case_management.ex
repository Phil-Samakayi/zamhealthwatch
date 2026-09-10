defmodule ZamHealthWatch.CaseManagement do
  @moduledoc """
  The CaseManagement context.

  Owns the individual case record - who reported it, at which facility,
  for which disease, and where it sits in its `:suspected` -> `:confirmed`
  -> `:resolved` lifecycle (per the brief's "Case Management" module).
  Aggregate views (case counts by district, trends over time - the
  brief's "Disease Surveillance" module) are queries over this same
  `cases` table, not a separate schema, so for now they live here too
  rather than in a still-empty context split off before there's
  anything distinct to split. Revisit if/when aggregation logic grows
  enough to justify its own boundary.
  """

  import Ecto.Query, warn: false
  alias ZamHealthWatch.Repo

  alias ZamHealthWatch.CaseManagement.Case

  @doc """
  Subscribes to notifications about any case changes.

  The broadcasted messages match the pattern:

    * {:created, %Case{}}
    * {:updated, %Case{}}

  """
  def subscribe_cases do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "cases")
  end

  defp broadcast_case(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "cases", message)
  end

  @doc """
  Returns the list of cases, most recently reported first.

  Ordered for the live case list (`CaseLive.Index`) - a plain `Repo.all/1`
  has no defined order, and binary_id primary keys don't happen to sort
  chronologically, so newest-first has to be explicit.

  ## Examples

      iex> list_cases()
      [%Case{}, ...]

  """
  def list_cases do
    Repo.all(from c in Case, order_by: [desc: c.inserted_at])
  end

  @doc """
  Returns the list of cases reported at a given facility.

  ## Examples

      iex> list_cases_by_facility(facility_id)
      [%Case{}, ...]

  """
  def list_cases_by_facility(facility_id) do
    Repo.all_by(Case, facility_id: facility_id)
  end

  @doc """
  Gets a single case.

  Raises `Ecto.NoResultsError` if the Case does not exist.

  ## Examples

      iex> get_case!(123)
      %Case{}

      iex> get_case!(456)
      ** (Ecto.NoResultsError)

  """
  def get_case!(id), do: Repo.get!(Case, id)

  @doc """
  Reports a new case.

  Always starts `:suspected` - see `Case.changeset/2`.

  ## Examples

      iex> create_case(%{field: value})
      {:ok, %Case{}}

      iex> create_case(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_case(attrs) do
    with {:ok, case = %Case{}} <-
           %Case{}
           |> Case.changeset(attrs)
           |> Repo.insert() do
      broadcast_case({:created, case})
      {:ok, case}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking case changes.

  ## Examples

      iex> change_case(case)
      %Ecto.Changeset{data: %Case{}}

  """
  def change_case(%Case{} = case, attrs \\ %{}) do
    Case.changeset(case, attrs)
  end

  @doc """
  Moves a case through its lifecycle (`:suspected` -> `:confirmed` -> `:resolved`).

  ## Examples

      iex> update_case_status(case, %{status: :confirmed})
      {:ok, %Case{}}

      iex> update_case_status(case, %{status: :bad_status})
      {:error, %Ecto.Changeset{}}

  """
  def update_case_status(%Case{} = case, attrs) do
    with {:ok, case = %Case{}} <-
           case
           |> Case.status_changeset(attrs)
           |> Repo.update() do
      broadcast_case({:updated, case})
      {:ok, case}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking a case's status change.

  ## Examples

      iex> change_case_status(case)
      %Ecto.Changeset{data: %Case{}}

  """
  def change_case_status(%Case{} = case, attrs \\ %{}) do
    Case.status_changeset(case, attrs)
  end

  @doc """
  Returns the total number of reported cases.

  ## Examples

      iex> count_cases()
      7

  """
  def count_cases do
    Repo.aggregate(Case, :count, :id)
  end

  @doc """
  Returns case counts grouped by disease, as `%{disease => count}`.

  A disease with zero cases is simply absent from the map rather than
  present with `0` - grouping by an `Ecto.Enum` field only ever produces
  rows that actually exist. Zero-filling the full set of disease values
  for display (so a dashboard can show every disease's tile even at
  zero) is a presentation concern, left to the caller - same division
  of labour as `list_facilities/0` staying name-only and `CaseLive.Index`
  composing `facilities_by_id` on top of it.

  ## Examples

      iex> count_cases_by_disease()
      %{cholera: 3, malaria: 1}

  """
  def count_cases_by_disease do
    Repo.all(from c in Case, group_by: c.disease, select: {c.disease, count(c.id)})
    |> Map.new()
  end

  @doc """
  Returns case counts grouped by status, as `%{status => count}`.

  Same zero-filling note as `count_cases_by_disease/0` applies.

  ## Examples

      iex> count_cases_by_status()
      %{suspected: 2, confirmed: 1}

  """
  def count_cases_by_status do
    Repo.all(from c in Case, group_by: c.status, select: {c.status, count(c.id)})
    |> Map.new()
  end

  @doc """
  Returns case counts grouped by facility, as `%{facility_id => count}`.

  Facility *names* aren't joined in here - `CaseManagement` and
  `Geography` are deliberately decoupled (no cross-context
  associations), so a caller wanting names composes this map with
  `Geography.list_facilities/0` in memory, same pattern as
  `CaseLive.Index`'s `facilities_by_id`.

  Only facilities with at least one case appear - there's no row to
  group by for a facility with zero cases.

  ## Examples

      iex> count_cases_by_facility()
      %{"facility-uuid" => 4}

  """
  def count_cases_by_facility do
    Repo.all(from c in Case, group_by: c.facility_id, select: {c.facility_id, count(c.id)})
    |> Map.new()
  end
end
