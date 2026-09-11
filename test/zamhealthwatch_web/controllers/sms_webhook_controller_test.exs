defmodule ZamHealthWatchWeb.SmsWebhookControllerTest do
  use ZamHealthWatchWeb.ConnCase, async: false

  import ZamHealthWatch.GeographyFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.SmsReporting

  # This is the one test module that starts SmsReporting.Pipeline under
  # its real, default (unqualified) name - the same name
  # SmsReporting.Pipeline.push/1 targets by default, and the same name
  # ZamHealthWatch.Application would use in dev/prod. Every other test
  # touching the pipeline (sms_reporting_test.exs) deliberately uses its
  # own uniquely-named instance instead, so there's no risk of two tests
  # racing to register the same name. async: false, same Sandbox
  # {:shared, self()} reasoning as sms_reporting_test.exs.
  setup do
    Sandbox.mode(Repo, {:shared, self()})
    start_supervised!(SmsReporting.Pipeline)
    on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    :ok
  end

  describe "POST /webhooks/sms" do
    test "responds 200 and actually creates a case for a well-formed inbound SMS", %{conn: conn} do
      facility = facility_fixture(%{code: "UTH"})

      conn =
        post(conn, ~p"/webhooks/sms", %{
          "from" => "+260971234567",
          "text" => "REPORT CHOLERA UTH",
          "to" => "384",
          "id" => "abc123",
          "date" => "2026-09-11T00:00:00Z"
        })

      assert conn.status == 200

      wait_until(fn ->
        Enum.any?(CaseManagement.list_cases(), &(&1.facility_id == facility.id))
      end)

      assert [case_record] = CaseManagement.list_cases()
      assert case_record.disease == :cholera
      assert case_record.facility_id == facility.id
    end

    test "responds 200 even for a payload missing from/text", %{conn: conn} do
      conn = post(conn, ~p"/webhooks/sms", %{"to" => "384"})
      assert conn.status == 200
      assert CaseManagement.list_cases() == []
    end

    test "responds 200 but creates no case for an unresolvable report", %{conn: conn} do
      conn =
        post(conn, ~p"/webhooks/sms", %{"from" => "+260971234567", "text" => "not a report"})

      assert conn.status == 200
      assert CaseManagement.list_cases() == []
    end
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts <= 0 ->
        flunk("condition not met in time")

      true ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)
    end
  end
end
