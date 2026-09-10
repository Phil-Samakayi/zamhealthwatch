defmodule ZamHealthWatch.Geography.District do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "districts" do
    field :name, :string
    field :province, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(district, attrs) do
    district
    |> cast(attrs, [:name, :province])
    |> validate_required([:name, :province])
  end
end
