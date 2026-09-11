defmodule ZamHealthWatch.DrugAvailability.DrugStock do
  use Ecto.Schema
  import Ecto.Changeset

  @medicine_options [
    {"ORS (Oral Rehydration Salts)", :ors},
    {"IV Fluids (Ringer's Lactate)", :iv_fluids},
    {"Artemether-Lumefantrine", :al},
    {"Ciprofloxacin", :ciprofloxacin},
    {"Ceftriaxone", :ceftriaxone}
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "drug_stocks" do
    field :medicine, Ecto.Enum, values: [:ors, :iv_fluids, :al, :ciprofloxacin, :ceftriaxone]
    field :quantity_on_hand, :integer
    field :reorder_level, :integer
    field :facility_id, :binary_id
    field :reported_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A drug stock record changeset - one submission covering a given
  facility/medicine combination (the brief's own "by facility"
  framing). Same "reported once, no lifecycle" shape as
  `VaccinationMonitoring.VaccinationRecord.changeset/2` - a stock count
  gets corrected by a new submission, not edited in place, so this is
  the only changeset this schema needs.

  `facility_id` and `reported_by_id` are checked against
  `Geography.Facility` and `Accounts.User` via `foreign_key_constraint/2`
  rather than by reaching into those schemas directly, same decoupling
  as every other context in this project.
  """
  def changeset(stock, attrs) do
    stock
    |> cast(attrs, [:medicine, :quantity_on_hand, :reorder_level, :facility_id, :reported_by_id])
    |> validate_required([
      :medicine,
      :quantity_on_hand,
      :reorder_level,
      :facility_id,
      :reported_by_id
    ])
    |> validate_number(:quantity_on_hand, greater_than_or_equal_to: 0)
    |> validate_number(:reorder_level, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:facility_id)
    |> foreign_key_constraint(:reported_by_id)
  end

  @doc """
  Returns the `{label, value}` options list for every valid `medicine`
  value, in display order - same "single source of truth on the schema"
  pattern `Case.disease_options/0` and `VaccinationRecord.antigen_options/0`
  already established.

  Scoped to essential medicines that map to this project's five tracked
  diseases (cholera, malaria, typhoid, COVID-19, measles), not a general
  pharmacy formulary - same "only what a real use case needs" reasoning
  applied to `Case.disease_options/0` itself.

  ## Examples

      iex> medicine_options()
      [{"ORS (Oral Rehydration Salts)", :ors}, ...]

  """
  def medicine_options, do: @medicine_options

  @doc """
  Returns a human-readable label for a `medicine` value, looked up in
  `medicine_options/0` rather than derived with `Phoenix.Naming.humanize/1` -
  same reasoning as `Case.disease_label/1` and `VaccinationRecord.antigen_label/1`
  (humanize can't produce "ORS (Oral Rehydration Salts)" from `:ors`).

  ## Examples

      iex> medicine_label(:al)
      "Artemether-Lumefantrine"

  """
  def medicine_label(medicine) do
    Enum.find_value(@medicine_options, Phoenix.Naming.humanize(medicine), fn {label, value} ->
      value == medicine && label
    end)
  end

  @doc """
  Returns `true` if `quantity_on_hand` is below `reorder_level` - the
  brief's own "flags shortages" framing, computed here (Information
  Expert: the schema holding both numbers is what answers "is this a
  shortage", not the context or the LiveView) rather than persisted as
  a separate column that could drift out of sync with the two numbers
  it's derived from.

  ## Examples

      iex> shortage?(%DrugStock{quantity_on_hand: 10, reorder_level: 50})
      true

      iex> shortage?(%DrugStock{quantity_on_hand: 50, reorder_level: 50})
      false

  """
  def shortage?(%__MODULE__{quantity_on_hand: qty, reorder_level: reorder}) do
    qty < reorder
  end
end
