defmodule ZamHealthWatch.HospitalCapacityFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ZamHealthWatch.HospitalCapacity` context.
  """

  alias ZamHealthWatch.AccountsFixtures
  alias ZamHealthWatch.GeographyFixtures

  @doc """
  Generate a capacity report.

  `facility_id`/`reported_by_id` are created on demand via the
  `Geography`/`Accounts` fixtures when not supplied, same pattern every
  other fixture module in this project already uses for its own
  foreign keys.
  """
  def capacity_report_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    facility_id = Map.get(attrs, :facility_id) || GeographyFixtures.facility_fixture().id
    reported_by_id = Map.get(attrs, :reported_by_id) || AccountsFixtures.user_fixture().id

    attrs =
      Enum.into(attrs, %{
        total_beds: 100,
        occupied_beds: 50,
        icu_beds_total: 10,
        icu_beds_occupied: 4,
        admissions_today: 8,
        facility_id: facility_id,
        reported_by_id: reported_by_id
      })

    {:ok, report} = ZamHealthWatch.HospitalCapacity.record_capacity(attrs)
    report
  end
end
