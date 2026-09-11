defmodule ZamHealthWatch.DrugAvailability do
  @moduledoc """
  The DrugAvailability context - the brief's "stock levels of essential
  medicines by facility; flags shortages that compound an active
  outbreak" module.

  Scoped down for this first slice (full reasoning in docs/ITERATIONS.md):

    * Reported at *facility* level (`facility_id`, not `district_id`) -
      the brief's own phrasing is "by facility", matching `Case`/`LabTest`'s
      existing facility-level granularity rather than `VaccinationMonitoring`'s
      district-level one. Different modules, different natural grain -
      no attempt made to force them to match.
    * A stock count is reported once, not advanced through a lifecycle -
      same "no request/confirm two-phase workflow, no editing yet" shape
      `VaccinationMonitoring` already settled on, for the same reason:
      there's no second phase to a stock count, it either gets corrected
      by a new submission or it doesn't.
    * `reorder_level` is entered per submission, not looked up from a
      fixed table of "safe stock levels" per medicine - real consumption
      varies enough by facility that a single global threshold per
      medicine would be a guessed-at rule with no real data behind it.
      Whoever reports the count is trusted to know what a shortage means
      at their facility.
    * The brief's "flags shortages that compound an active outbreak"
      half is only half built this slice: shortages are flagged (see
      `DrugStock.shortage?/1`), but nothing here cross-references an
      active case's disease against the medicine that treats it. That
      correlation is a real, separate piece of analysis - deliberately
      not guessed at here, same as `VaccinationMonitoring` leaving its
      own risk-scoring integration for a dedicated follow-on iteration
      rather than bolting on something half-considered.

  Depends on `Geography` (a record's `facility_id`) and `Accounts` (its
  `reported_by_id`) the same decoupled way every other context in this
  project does - `foreign_key_constraint/2` on the schema, no
  cross-context associations.
  """

  import Ecto.Query, warn: false
  alias ZamHealthWatch.Repo

  alias ZamHealthWatch.DrugAvailability.DrugStock

  @doc """
  Subscribes to notifications about any drug stock changes.

  The broadcasted messages match the pattern:

    * {:created, %DrugStock{}}

  Own `"drug_stocks"` topic, not reused from `"cases"`/`"facilities"`/
  `"lab_tests"`/`"vaccination_records"` - same per-context topic
  precedent every other module in this project already set.
  """
  def subscribe_drug_stocks do
    Phoenix.PubSub.subscribe(ZamHealthWatch.PubSub, "drug_stocks")
  end

  defp broadcast_drug_stock(message) do
    Phoenix.PubSub.broadcast(ZamHealthWatch.PubSub, "drug_stocks", message)
  end

  @doc """
  Returns the list of drug stock records, most recently reported first.

  ## Examples

      iex> list_drug_stocks()
      [%DrugStock{}, ...]

  """
  def list_drug_stocks do
    Repo.all(from d in DrugStock, order_by: [desc: d.inserted_at])
  end

  @doc """
  Gets a single drug stock record.

  Raises `Ecto.NoResultsError` if it does not exist.

  ## Examples

      iex> get_drug_stock!(123)
      %DrugStock{}

  """
  def get_drug_stock!(id), do: Repo.get!(DrugStock, id)

  @doc """
  Records a new drug stock submission.

  ## Examples

      iex> record_stock(%{field: value})
      {:ok, %DrugStock{}}

      iex> record_stock(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def record_stock(attrs) do
    with {:ok, stock = %DrugStock{}} <-
           %DrugStock{}
           |> DrugStock.changeset(attrs)
           |> Repo.insert() do
      broadcast_drug_stock({:created, stock})
      {:ok, stock}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking drug stock changes.

  ## Examples

      iex> change_drug_stock(stock)
      %Ecto.Changeset{data: %DrugStock{}}

  """
  def change_drug_stock(%DrugStock{} = stock, attrs \\ %{}) do
    DrugStock.changeset(stock, attrs)
  end
end
