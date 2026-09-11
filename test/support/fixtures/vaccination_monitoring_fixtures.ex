defmodule ZamHealthWatch.VaccinationMonitoringFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ZamHealthWatch.VaccinationMonitoring` context.
  """

  alias ZamHealthWatch.AccountsFixtures
  alias ZamHealthWatch.GeographyFixtures

  @doc """
  Generate a vaccination record.

  `district_id`/`reported_by_id` are created on demand via the
  `Geography`/`Accounts` fixtures when not supplied, same pattern
  `CaseManagementFixtures.case_fixture/1` and
  `LabReportingFixtures.lab_test_fixture/1` already use for their own
  foreign keys.
  """
  def vaccination_record_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    district_id = Map.get(attrs, :district_id) || GeographyFixtures.district_fixture().id
    reported_by_id = Map.get(attrs, :reported_by_id) || AccountsFixtures.user_fixture().id

    attrs =
      Enum.into(attrs, %{
        antigen: :measles_rubella,
        campaign: "Routine - Sep 2026",
        doses_administered: 80,
        target_population: 100,
        district_id: district_id,
        reported_by_id: reported_by_id
      })

    {:ok, record} = ZamHealthWatch.VaccinationMonitoring.record_vaccination(attrs)
    record
  end
end
