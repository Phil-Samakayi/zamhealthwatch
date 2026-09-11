defmodule ZamHealthWatch.LabReportingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ZamHealthWatch.LabReporting` context.
  """

  alias ZamHealthWatch.AccountsFixtures
  alias ZamHealthWatch.CaseManagementFixtures

  @doc """
  Generate a lab test.

  `case_id`/`requested_by_id` are created on demand via the
  `CaseManagement`/`Accounts` fixtures when not supplied, same pattern
  `CaseManagementFixtures.case_fixture/1` already uses for its own
  `facility_id`/`reported_by_id`.
  """
  def lab_test_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    case_id = Map.get(attrs, :case_id) || CaseManagementFixtures.case_fixture().id
    requested_by_id = Map.get(attrs, :requested_by_id) || AccountsFixtures.user_fixture().id

    attrs =
      Enum.into(attrs, %{
        case_id: case_id,
        requested_by_id: requested_by_id
      })

    {:ok, lab_test} = ZamHealthWatch.LabReporting.request_test(attrs)
    lab_test
  end
end
