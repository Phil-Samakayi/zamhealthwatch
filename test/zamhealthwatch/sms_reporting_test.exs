defmodule ZamHealthWatch.SmsReportingTest do
  use ZamHealthWatch.DataCase, async: false

  import ExUnit.CaptureLog
  import ZamHealthWatch.GeographyFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.SmsReporting
  alias ZamHealthWatch.SmsReporting.Pipeline

  describe "report_from_sms/2" do
    test "creates a case from a well-formed report" do
      facility = facility_fixture(%{code: "UTH"})

      assert {:ok, case_record} =
               SmsReporting.report_from_sms("+260971234567", "REPORT CHOLERA UTH")

      assert case_record.disease == :cholera
      assert case_record.facility_id == facility.id
      assert case_record.status == :suspected
    end

    test "is case-insensitive and tolerates extra whitespace" do
      facility_fixture(%{code: "UTH"})

      assert {:ok, case_record} =
               SmsReporting.report_from_sms("+260971234567", "  report   cholera   uth  ")

      assert case_record.disease == :cholera
    end

    test "accepts COVID as an alias for covid19" do
      facility_fixture(%{code: "UTH"})

      assert {:ok, case_record} = SmsReporting.report_from_sms("+260971234567", "REPORT COVID UTH")
      assert case_record.disease == :covid19
    end

    test "finds or creates a user by phone, reusing it across reports" do
      facility_fixture(%{code: "UTH"})
      phone = "+260971234567"

      assert {:ok, case_a} = SmsReporting.report_from_sms(phone, "REPORT CHOLERA UTH")
      assert {:ok, case_b} = SmsReporting.report_from_sms(phone, "REPORT MALARIA UTH")

      assert case_a.reported_by_id == case_b.reported_by_id

      assert {:ok, user} = Accounts.find_or_create_sms_reporter(phone)
      assert user.id == case_a.reported_by_id
      assert user.role == nil
    end

    test "rejects unparseable text" do
      assert {:error, :unrecognized_format} =
               SmsReporting.report_from_sms("+260971234567", "hello")
    end

    test "rejects an unrecognized disease" do
      facility_fixture(%{code: "UTH"})

      assert {:error, {:unknown_disease, "FLU"}} =
               SmsReporting.report_from_sms("+260971234567", "REPORT FLU UTH")
    end

    test "rejects an unknown facility code" do
      assert {:error, {:unknown_facility, "NOPE"}} =
               SmsReporting.report_from_sms("+260971234567", "REPORT CHOLERA NOPE")
    end
  end

  describe "confirmation_message/1" do
    test "confirms success, naming the disease and facility" do
      facility = facility_fixture(%{code: "UTH", name: "UTH"})
      {:ok, case_record} = SmsReporting.report_from_sms("+260971234567", "REPORT CHOLERA UTH")

      message = SmsReporting.confirmation_message({:ok, case_record})

      assert message =~ "Cholera"
      assert message =~ facility.name
    end

    test "explains an unrecognized format" do
      message = SmsReporting.confirmation_message({:error, :unrecognized_format})
      assert message =~ "REPORT"
    end

    test "names the unrecognized disease" do
      message = SmsReporting.confirmation_message({:error, {:unknown_disease, "FLU"}})
      assert message =~ "FLU"
    end

    test "names the unrecognized facility code" do
      message = SmsReporting.confirmation_message({:error, {:unknown_facility, "NOPE"}})
      assert message =~ "NOPE"
    end

    test "falls back to a generic message for any other error" do
      message = SmsReporting.confirmation_message({:error, :something_unexpected})
      assert message =~ "try again"
    end
  end

  # These tests exercise the real Broadway wiring (Producer's demand-driven
  # dispatch -> Pipeline.handle_message/3 -> report_from_sms/2 -> Repo),
  # not just report_from_sms/2 directly - that plumbing is the actual
  # thing this iteration exists to prove out. Each test starts its own
  # uniquely-named Pipeline instance (never the app's default-named one,
  # which stays off in :test - see config/test.exs) so tests can't collide
  # on Broadway's process registration.
  describe "the Broadway pipeline" do
    setup do
      # The Broadway processor process that ends up calling Repo isn't
      # the test process, and isn't a single well-known pid the way
      # PublicAlerts.Subscriber's GenServer is - there's no one pid to
      # Sandbox.allow/3. Shared mode lets any process use this test's
      # checked-out connection instead. Known trade-off: shared mode is
      # process-wide, not perfectly isolated from other concurrently
      # running async tests elsewhere in the suite during this narrow
      # window - same category of imperfection as Iteration 1's
      # temporary global Logger-level change. async: false on this
      # module is what keeps it from colliding with itself.
      Sandbox.mode(Repo, {:shared, self()})
      on_exit(fn -> Sandbox.mode(Repo, :manual) end)

      # Same Logger-level dance as PublicAlerts.AlertWorkerTest - needed
      # here too now that handle_message/3 sends a reply through
      # SmsGateway.Logger (the default in :test), which logs at :info,
      # below this project's :warning test log level.
      original_level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: original_level) end)
    end

    test "a pushed message flows through Producer -> Pipeline -> a real case, and replies" do
      facility = facility_fixture(%{code: "NTH"})
      name = :"sms_pipeline_test_#{System.unique_integer([:positive])}"
      start_supervised!({Pipeline, name: name})

      log =
        capture_log(fn ->
          Pipeline.push(name, %{from: "+260977000111", text: "REPORT TYPHOID NTH"})

          wait_until(fn ->
            Enum.any?(CaseManagement.list_cases(), &(&1.facility_id == facility.id))
          end)
        end)

      assert [case_record] = CaseManagement.list_cases()
      assert case_record.disease == :typhoid
      assert case_record.facility_id == facility.id

      # The confirmation reply (sent via SmsGateway.Logger, the :test
      # default) landed in the log too.
      assert log =~ "+260977000111"
      assert log =~ "Typhoid"
    end

    test "a rejected message doesn't crash the pipeline or create a case, and still replies" do
      name = :"sms_pipeline_test_#{System.unique_integer([:positive])}"
      start_supervised!({Pipeline, name: name})

      log =
        capture_log(fn ->
          Pipeline.push(name, %{from: "+260977000111", text: "not a report"})

          # Follow the bad message with a good one on the same pipeline -
          # this only passes if the pipeline is still alive and taking
          # demand right after rejecting a message, not just that a case
          # never appears.
          facility_fixture(%{code: "MMH"})
          Pipeline.push(name, %{from: "+260977000111", text: "REPORT MEASLES MMH"})

          wait_until(fn -> CaseManagement.list_cases() != [] end)
        end)

      assert [case_record] = CaseManagement.list_cases()
      assert case_record.disease == :measles

      # The rejected message's own reply (not the accepted one's).
      assert log =~ "couldn't read that report"
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
