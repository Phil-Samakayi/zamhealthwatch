defmodule ZamHealthWatch.Geography.Facility do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "facilities" do
    field :name, :string
    field :district_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(facility, attrs) do
    facility
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
