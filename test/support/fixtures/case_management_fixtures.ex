defmodule ZamHealthWatch.CaseManagementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ZamHealthWatch.CaseManagement` context.
  """

  alias ZamHealthWatch.AccountsFixtures
  alias ZamHealthWatch.GeographyFixtures

  @doc """
  Generate a case.

  `facility_id`/`reported_by_id` are created on demand via the
  `Geography`/`Accounts` fixtures when not supplied, same pattern as
  `Facility` pulling in a fixture-created `District` where needed.
  """
  def case_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    facility_id = Map.get(attrs, :facility_id) || GeographyFixtures.facility_fixture().id
    reported_by_id = Map.get(attrs, :reported_by_id) || AccountsFixtures.user_fixture().id

    attrs =
      Enum.into(attrs, %{
        disease: :malaria,
        facility_id: facility_id,
        reported_by_id: reported_by_id
      })

    {:ok, case} = ZamHealthWatch.CaseManagement.create_case(attrs)
    case
  end
end
