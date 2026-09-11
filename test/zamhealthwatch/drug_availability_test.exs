defmodule ZamHealthWatch.DrugAvailabilityTest do
  use ZamHealthWatch.DataCase

  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock

  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures

  describe "list_drug_stocks/0" do
    test "returns an empty list with no records" do
      assert DrugAvailability.list_drug_stocks() == []
    end

    test "returns every record" do
      a = drug_stock_fixture()
      b = drug_stock_fixture()

      assert DrugAvailability.list_drug_stocks() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([a.id, b.id])
    end
  end

  describe "get_drug_stock!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        DrugAvailability.get_drug_stock!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the record with the given id" do
      %{id: id} = drug_stock_fixture()
      assert %DrugStock{id: ^id} = DrugAvailability.get_drug_stock!(id)
    end
  end

  describe "record_stock/1" do
    test "records with valid data" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:ok, %DrugStock{} = stock} =
               DrugAvailability.record_stock(%{
                 medicine: :al,
                 quantity_on_hand: 30,
                 reorder_level: 50,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert stock.medicine == :al
      assert stock.quantity_on_hand == 30
      assert stock.reorder_level == 50
      assert stock.facility_id == facility.id
      assert stock.reported_by_id == user.id
    end

    test "requires medicine, quantity_on_hand, reorder_level, facility_id, and reported_by_id" do
      assert {:error, changeset} = DrugAvailability.record_stock(%{})

      assert %{
               medicine: ["can't be blank"],
               quantity_on_hand: ["can't be blank"],
               reorder_level: ["can't be blank"],
               facility_id: ["can't be blank"],
               reported_by_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects a negative quantity_on_hand" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               DrugAvailability.record_stock(%{
                 medicine: :al,
                 quantity_on_hand: -1,
                 reorder_level: 50,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert %{quantity_on_hand: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "rejects a negative reorder_level" do
      facility = facility_fixture()
      user = user_fixture()

      assert {:error, changeset} =
               DrugAvailability.record_stock(%{
                 medicine: :al,
                 quantity_on_hand: 30,
                 reorder_level: -1,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert %{reorder_level: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "rejects a facility_id that doesn't reference a real facility" do
      user = user_fixture()

      assert {:error, changeset} =
               DrugAvailability.record_stock(%{
                 medicine: :al,
                 quantity_on_hand: 30,
                 reorder_level: 50,
                 facility_id: Ecto.UUID.generate(),
                 reported_by_id: user.id
               })

      assert %{facility_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects a reported_by_id that doesn't reference a real user" do
      facility = facility_fixture()

      assert {:error, changeset} =
               DrugAvailability.record_stock(%{
                 medicine: :al,
                 quantity_on_hand: 30,
                 reorder_level: 50,
                 facility_id: facility.id,
                 reported_by_id: Ecto.UUID.generate()
               })

      assert %{reported_by_id: ["does not exist"]} = errors_on(changeset)
    end

    test "broadcasts the created record" do
      facility = facility_fixture()
      user = user_fixture()
      DrugAvailability.subscribe_drug_stocks()

      assert {:ok, stock} =
               DrugAvailability.record_stock(%{
                 medicine: :al,
                 quantity_on_hand: 30,
                 reorder_level: 50,
                 facility_id: facility.id,
                 reported_by_id: user.id
               })

      assert_receive {:created, ^stock}
    end
  end

  describe "change_drug_stock/2" do
    test "returns a drug stock changeset" do
      assert %Ecto.Changeset{} = changeset = DrugAvailability.change_drug_stock(%DrugStock{})

      assert changeset.required == [
               :medicine,
               :quantity_on_hand,
               :reorder_level,
               :facility_id,
               :reported_by_id
             ]
    end
  end

  describe "DrugStock.shortage?/1" do
    test "returns true when quantity_on_hand is below reorder_level" do
      stock = drug_stock_fixture(%{quantity_on_hand: 20, reorder_level: 50})
      assert DrugStock.shortage?(stock)
    end

    test "returns false when quantity_on_hand is at or above reorder_level" do
      stock = drug_stock_fixture(%{quantity_on_hand: 50, reorder_level: 50})
      refute DrugStock.shortage?(stock)
    end
  end

  describe "DrugStock.medicine_options/0 and medicine_label/1" do
    test "medicine_options returns every valid medicine with a label" do
      assert {"ORS (Oral Rehydration Salts)", :ors} in DrugStock.medicine_options()
    end

    test "medicine_label looks up the label" do
      assert DrugStock.medicine_label(:al) == "Artemether-Lumefantrine"
    end

    test "medicine_label falls back to humanize for an unmapped value" do
      assert DrugStock.medicine_label(:unknown_medicine) == "Unknown medicine"
    end
  end
end
