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
  Returns the status a case would move to next in its one-directional
  lifecycle (`:suspected` -> `:confirmed` -> `:resolved`), or `nil` once
  `:resolved` - there's nowhere further to advance to.

  `update_case_status/2` itself still allows setting *any* valid status
  regardless of the current one (Iteration 1 deliberately left that
  permissive at the data layer - see `Case.status_changeset/2` - since
  there was no case-management screen yet to make a stricter rule
  meaningful). Now that `CaseLive.Index` has one, this is that rule,
  layered on top rather than tightened in the changeset itself, so a
  future consumer that legitimately needs an arbitrary status set isn't
  blocked by it.

  ## Examples

      iex> next_status(:suspected)
      :confirmed

      iex> next_status(:resolved)
      nil

  """
  def next_status(:suspected), do: :confirmed
  def next_status(:confirmed), do: :resolved
  def next_status(:resolved), do: nil

  @doc """
  Advances a case to its next lifecycle status on behalf of a user
  holding `role`.

  Two checks happen here, not only in `CaseLive.Index`'s rendering - a
  forged event can't skip either one, the same server-side-enforcement
  precedent `with_reporter/2` already set for `reported_by_id`:

    * `role` must be assigned (not `nil`) - any of `Accounts.User`'s
      three roles qualifies. This slice doesn't yet distinguish *which*
      role may do what (e.g. only `:moh_admin` resolving a case) - no
      real use case has decided that yet, so it isn't guessed at here,
      same reasoning this project has applied to every other
      not-yet-needed distinction. Revisit once one exists.
    * the case must actually have a next status (see `next_status/1`) -
      a `:resolved` case is a terminal state.

  Takes a plain `role` atom (or `nil`), not an `%Accounts.User{}` struct -
  `CaseManagement` stays decoupled from `Accounts`'s schema the same way
  it already is from `Geography.Facility`'s, so the caller (`CaseLive.Index`,
  via `current_scope.user.role`) is what bridges the two contexts, not
  this one reaching into the other's data directly.

  ## Examples

      iex> advance_case_status(case, :health_worker)
      {:ok, %Case{}}

      iex> advance_case_status(case, nil)
      {:error, :unauthorized}

      iex> advance_case_status(%Case{status: :resolved}, :health_worker)
      {:error, :no_next_status}

  """
  def advance_case_status(%Case{} = case, role) do
    cond do
      is_nil(role) -> {:error, :unauthorized}
      is_nil(next_status(case.status)) -> {:error, :no_next_status}
      true -> update_case_status(case, %{status: next_status(case.status)})
    end
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

  @doc """
  Returns case counts grouped by facility for cases reported in
  `[start_dt, end_dt)`, as `%{facility_id => count}`.

  Built for `PredictiveAnalytics`'s weekly trend buckets, but a general
  enough primitive (an arbitrary time window, not "the last N days") to
  reuse anywhere else a windowed count is needed later. Uses `inserted_at`
  as "when the case was reported" - there's no separate
  "when symptoms/the outbreak actually started" field on `Case`, so
  report time is the closest proxy this system has.

  Same zero-omission and name-decoupling notes as `count_cases_by_facility/0`
  apply: a facility with no cases in the window is simply absent, and
  facility names aren't joined in here.

  ## Examples

      iex> count_cases_by_facility_between(~U[2026-09-01 00:00:00Z], ~U[2026-09-08 00:00:00Z])
      %{"facility-uuid" => 2}

  """
  def count_cases_by_facility_between(start_dt, end_dt) do
    Repo.all(
      from c in Case,
        where: c.inserted_at >= ^start_dt and c.inserted_at < ^end_dt,
        group_by: c.facility_id,
        select: {c.facility_id, count(c.id)}
    )
    |> Map.new()
  end
end
