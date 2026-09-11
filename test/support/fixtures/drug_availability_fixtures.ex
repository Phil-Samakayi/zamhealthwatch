defmodule ZamHealthWatch.DrugAvailabilityFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ZamHealthWatch.DrugAvailability` context.
  """

  alias ZamHealthWatch.AccountsFixtures
  alias ZamHealthWatch.GeographyFixtures

  @doc """
  Generate a drug stock record.

  `facility_id`/`reported_by_id` are created on demand via the
  `Geography`/`Accounts` fixtures when not supplied, same pattern
  `CaseManagementFixtures.case_fixture/1`, `LabReportingFixtures.lab_test_fixture/1`,
  and `VaccinationMonitoringFixtures.vaccination_record_fixture/1` already
  use for their own foreign keys.
  """
  def drug_stock_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    facility_id = Map.get(attrs, :facility_id) || GeographyFixtures.facility_fixture().id
    reported_by_id = Map.get(attrs, :reported_by_id) || AccountsFixtures.user_fixture().id

    attrs =
      Enum.into(attrs, %{
        medicine: :ors,
        quantity_on_hand: 80,
        reorder_level: 50,
        facility_id: facility_id,
        reported_by_id: reported_by_id
      })

    {:ok, stock} = ZamHealthWatch.DrugAvailability.record_stock(attrs)
    stock
  end
end
