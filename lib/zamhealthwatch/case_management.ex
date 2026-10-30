defmodule ZamHealthWatch.CaseManagement do
  @moduledoc """
  The CaseManagement context.

  Owns the individual case record - who reported it, at which facility,
  for which disease, its classification (`:suspected`, `:confirmed`, or
  `:not_a_case`), and the patient's outcome (`:recovered` or `:died`)
  once one is known (per the brief's "Case Management" module).
  Aggregate views (case counts by district, trends over time - the
  brief's "Disease Surveillance" module) are queries over this same
  `cases` table, not a separate schema, so for now they live here too
  rather than in a still-empty context split off before there's
  anything distinct to split. Revisit if/when aggregation logic grows
  enough to justify its own boundary.

  **Which cases count.** Since Iteration 15, every aggregate below
  except `count_cases_by_status/0` excludes `:not_a_case` - a case ruled
  out by a negative lab result was never a case, so it doesn't belong
  in a disease total, a facility's case count, a map marker, or a risk
  trend. That's the standard surveillance counting rule (suspected plus
  confirmed). `count_cases_by_status/0` still counts every
  classification, so a dashboard can show how many were ruled out.
  `list_cases/0` and `list_cases_by_facility/1` still return every
  record - the case list is a register of reports, not a total.
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
  Subscribes to notifications about a case's classification changing.

  The broadcasted messages match the pattern:

    * {:reclassified, %Case{}, previous_status}

  Sent whenever `status` actually changes - by a person confirming a
  case, or by a lab result being entered, corrected, or withdrawn - and
  never when it stays the same. Its own topic, separate from `"cases"`,
  on purpose (Iteration 15): every LiveView on `"cases"` pattern-matches
  `{:created, _}`/`{:updated, _}` only, and a new message shape there
  would crash each of them. Only something that cares about the
  *transition* (Public Alerts' "ruled out" follow-up) subscribes here.
  """
  def subscribe_reclassifications do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "case_reclassifications")
  end

  defp broadcast_reclassification(%Case{status: status}, status), do: :ok

  defp broadcast_reclassification(%Case{} = case_record, previous_status) do
    Phoenix.PubSub.broadcast(
      ZamHealthWatch.PubSub,
      "case_reclassifications",
      {:reclassified, case_record, previous_status}
    )
  end

  @doc """
  Returns the list of cases, most recently reported first.

  Ordered for the live case list (`CaseLive.Index`) - a plain `Repo.all/1`
  has no defined order, and binary_id primary keys don't happen to sort
  chronologically, so newest-first has to be explicit. Includes
  `:not_a_case` records (see the moduledoc).

  ## Examples

      iex> list_cases()
      [%Case{}, ...]

  """
  def list_cases do
    Repo.all(from c in Case, order_by: [desc: c.inserted_at])
  end

  @doc """
  Returns the list of cases reported at a given facility, most recently
  reported first.

  Defined since Iteration 0 but had no real caller until the Health
  Worker Portal landing page needed "this facility's recent cases" -
  ordered now the same way `list_cases/0` already is (`Repo.all_by/2`
  has no defined order on its own), rather than leaving an unordered
  list for its first real consumer to work around.

  ## Examples

      iex> list_cases_by_facility(facility_id)
      [%Case{}, ...]

  """
  def list_cases_by_facility(facility_id) do
    Repo.all(from c in Case, where: c.facility_id == ^facility_id, order_by: [desc: c.inserted_at])
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

  Always starts `:suspected` with no outcome - see `Case.changeset/2`.

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
  Sets a case's classification (`:suspected`, `:confirmed`, or
  `:not_a_case`).

  The unrestricted primitive - any valid value, from any current one.
  `LabReporting` uses it to apply what a result means, and a result can
  move a case in any direction. A *person's* manual change goes through
  `advance_case_status/2`, which only allows confirming a suspected case.

  ## Examples

      iex> update_case_status(case, %{status: :confirmed})
      {:ok, %Case{}}

      iex> update_case_status(case, %{status: :bad_status})
      {:error, %Ecto.Changeset{}}

  """
  def update_case_status(%Case{} = case_record, attrs) do
    with {:ok, updated = %Case{}} <-
           case_record
           |> Case.status_changeset(attrs)
           |> Repo.update() do
      broadcast_case({:updated, updated})
      broadcast_reclassification(updated, case_record.status)
      {:ok, updated}
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
  Returns the classification a person may move a case to by hand, or
  `nil` if there's none.

  Only `:suspected` -> `:confirmed`: confirming a case on clinical or
  epidemiological grounds (a patient linked to a known cluster, say) is
  something a health worker legitimately does without waiting for a lab.
  Ruling a case *out* is the lab's call, made through a negative result
  (see `LabReporting.record_result/3`), so there's no manual path to
  `:not_a_case`. Since Iteration 15 a confirmed case no longer has a
  manual next step either - "Resolve" used to be one, but closing a
  case is now recording its outcome (`record_outcome/3`), which isn't a
  classification at all.

  ## Examples

      iex> next_status(:suspected)
      :confirmed

      iex> next_status(:confirmed)
      nil

  """
  def next_status(:suspected), do: :confirmed
  def next_status(:confirmed), do: nil
  def next_status(:not_a_case), do: nil

  @doc """
  Moves a case to its next classification (see `next_status/1`) on
  behalf of a user holding `role`.

  Two checks happen here, not only in `CaseLive.Index`'s rendering - a
  forged event can't skip either one, the same server-side-enforcement
  precedent `with_reporter/2` already set for `reported_by_id`:

    * `role` must be assigned (not `nil`) - any of the assigned roles
      qualifies.
    * the case must actually have a next classification.

  Takes a plain `role` atom (or `nil`), not an `%Accounts.User{}` struct -
  `CaseManagement` stays decoupled from `Accounts`'s schema the same way
  it already is from `Geography.Facility`'s, so the caller (`CaseLive.Index`,
  via `current_scope.user.role`) is what bridges the two contexts.

  ## Examples

      iex> advance_case_status(case, :health_worker)
      {:ok, %Case{}}

      iex> advance_case_status(case, nil)
      {:error, :unauthorized}

      iex> advance_case_status(%Case{status: :confirmed}, :health_worker)
      {:error, :no_next_status}

  """
  def advance_case_status(%Case{} = case, role) do
    cond do
      is_nil(role) -> {:error, :unauthorized}
      is_nil(next_status(case.status)) -> {:error, :no_next_status}
      true -> confirm_clinically(case)
    end
  end

  # The only manual transition (`:suspected` -> `:confirmed`) also
  # records *that* a person confirmed it, so the confirmation survives
  # later lab-driven recalculation - see classification_for/2.
  defp confirm_clinically(%Case{} = case_record) do
    with {:ok, updated = %Case{}} <-
           case_record
           |> Case.clinical_confirmation_changeset()
           |> Repo.update() do
      broadcast_case({:updated, updated})
      broadcast_reclassification(updated, case_record.status)
      {:ok, updated}
    end
  end

  @doc """
  Returns the classification a case should have, given what its lab
  results say (`lab_verdict`) and whether a person confirmed it
  clinically.

  `lab_verdict` comes from `LabReporting`, which owns what results mean:
  `:positive` if any current result is positive, `:negative` if none is
  positive but at least one is negative, `:none` if there's no
  conclusive current result. Rules, in order:

    1. A positive result confirms the case. One positive outweighs
       negatives on other tests - a negative test can miss a real
       infection, a positive one rarely invents one.
    2. A negative result, with no positive, rules the case out - even
       one a person had confirmed clinically. A laboratory finding
       outranks a clinical impression; that's what the test was for.
    3. With no conclusive result, a clinical confirmation still stands.
    4. Otherwise the case is suspected.

  Because the result depends only on these facts, never on the case's
  previous status, recalculating after a lab result is corrected or
  withdrawn gives the right answer automatically. There's nothing to
  "undo".

  ## Examples

      iex> classification_for(:negative, ~U[2026-10-01 09:00:00Z])
      :not_a_case

      iex> classification_for(:none, ~U[2026-10-01 09:00:00Z])
      :confirmed

      iex> classification_for(:none, nil)
      :suspected

  """
  def classification_for(:positive, _clinically_confirmed_at), do: :confirmed
  def classification_for(:negative, _clinically_confirmed_at), do: :not_a_case
  def classification_for(:none, nil), do: :suspected
  def classification_for(:none, _clinically_confirmed_at), do: :confirmed

  @doc """
  Recalculates a case's classification from `lab_verdict` (see
  `classification_for/2`) and saves it if it changed. Called by
  `LabReporting` whenever one of the case's results is entered,
  corrected, or withdrawn. Returns `{:ok, case}` either way; nothing is
  written or broadcast when the classification is already right.
  """
  def apply_lab_verdict(%Case{} = case_record, lab_verdict) do
    case classification_for(lab_verdict, case_record.clinically_confirmed_at) do
      status when status == case_record.status -> {:ok, case_record}
      status -> update_case_status(case_record, %{status: status})
    end
  end

  @doc """
  Records the patient's outcome (`:recovered` or `:died`) on behalf of a
  user holding `role`.

  Rejected when:

    * `role` is `nil` - same rule as `advance_case_status/2`.
    * the case is `:not_a_case` - ruled out means there's no case of
      this disease to have an outcome *of*.
    * an outcome is already recorded - same "terminal once set" call
      `LabReporting.record_result/3` makes for a lab result, so a
      mis-click can't silently overwrite a recorded death. Correcting a
      wrong outcome is its own, audited action, not an overwrite.

  ## Examples

      iex> record_outcome(case, :recovered, :health_worker)
      {:ok, %Case{outcome: :recovered}}

      iex> record_outcome(%Case{status: :not_a_case}, :died, :health_worker)
      {:error, :not_a_case}

  """
  def record_outcome(%Case{} = case, outcome, role) do
    cond do
      is_nil(role) ->
        {:error, :unauthorized}

      case.status == :not_a_case ->
        {:error, :not_a_case}

      not is_nil(case.outcome) ->
        {:error, :outcome_already_recorded}

      true ->
        with {:ok, case = %Case{}} <-
               case
               |> Case.outcome_changeset(%{outcome: outcome})
               |> Repo.update() do
          broadcast_case({:updated, case})
          {:ok, case}
        end
    end
  end

  @doc """
  Returns `true` if any case record exists at all, `:not_a_case`
  included.

  For "is this database empty?" checks (`ZamHealthWatch.Demo`'s
  seed-once guard), where `count_cases/0` would be the wrong question:
  a database holding only ruled-out cases has zero *countable* cases
  but is not empty.
  """
  def any_cases? do
    Repo.exists?(Case)
  end

  @doc """
  Returns the number of countable cases - suspected or confirmed, not
  ruled out (see the moduledoc).

  ## Examples

      iex> count_cases()
      7

  """
  def count_cases do
    Repo.aggregate(countable(), :count, :id)
  end

  @doc """
  Returns countable case counts grouped by disease, as `%{disease => count}`.

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
    Repo.all(from c in countable(), group_by: c.disease, select: {c.disease, count(c.id)})
    |> Map.new()
  end

  @doc """
  Returns case counts grouped by classification, as `%{status => count}`.

  The one aggregate that includes `:not_a_case` - how many reports were
  ruled out is itself a useful surveillance figure. Same zero-filling
  note as `count_cases_by_disease/0` applies.

  ## Examples

      iex> count_cases_by_status()
      %{suspected: 2, confirmed: 1, not_a_case: 1}

  """
  def count_cases_by_status do
    Repo.all(from c in Case, group_by: c.status, select: {c.status, count(c.id)})
    |> Map.new()
  end

  @doc """
  Returns countable case counts grouped by recorded outcome, as
  `%{outcome => count}`. Cases with no outcome yet aren't included.

  ## Examples

      iex> count_cases_by_outcome()
      %{recovered: 4, died: 1}

  """
  def count_cases_by_outcome do
    Repo.all(
      from c in countable(),
        where: not is_nil(c.outcome),
        group_by: c.outcome,
        select: {c.outcome, count(c.id)}
    )
    |> Map.new()
  end

  @doc """
  Returns countable case counts grouped by facility, as `%{facility_id => count}`.

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
    Repo.all(from c in countable(), group_by: c.facility_id, select: {c.facility_id, count(c.id)})
    |> Map.new()
  end

  @doc """
  Returns countable case counts grouped by facility for cases reported in
  `[start_dt, end_dt)`, as `%{facility_id => count}`.

  Built for `PredictiveAnalytics`'s weekly trend buckets, but a general
  enough primitive (an arbitrary time window, not "the last N days") to
  reuse anywhere else a windowed count is needed later. Uses `inserted_at`
  as "when the case was reported" - there's no separate
  "when symptoms/the outbreak actually started" field on `Case`, so
  report time is the closest proxy this system has. Excluding
  `:not_a_case` matters most here: a cluster of reports that the lab
  ruled out shouldn't read as a rising outbreak.

  Same zero-omission and name-decoupling notes as `count_cases_by_facility/0`
  apply: a facility with no cases in the window is simply absent, and
  facility names aren't joined in here.

  ## Examples

      iex> count_cases_by_facility_between(~U[2026-09-01 00:00:00Z], ~U[2026-09-08 00:00:00Z])
      %{"facility-uuid" => 2}

  """
  def count_cases_by_facility_between(start_dt, end_dt) do
    Repo.all(
      from c in countable(),
        where: c.inserted_at >= ^start_dt and c.inserted_at < ^end_dt,
        group_by: c.facility_id,
        select: {c.facility_id, count(c.id)}
    )
    |> Map.new()
  end

  # Suspected or confirmed - the cases surveillance counts.
  defp countable do
    from c in Case, where: c.status != :not_a_case
  end
end
