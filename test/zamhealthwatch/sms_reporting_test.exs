defmodule ZamHealthWatch.SmsReportingTest do
  use ZamHealthWatch.DataCase, async: false

  import ExUnit.CaptureLog
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.SmsReporting
  alias ZamHealthWatch.SmsReporting.Pipeline

  describe "report_from_sms/2 - who can report" do
    test "refuses an unregistered number, creating no account and no case" do
      facility_fixture(%{code: "UTH"})
      users_before = length(Accounts.list_users())

      assert SmsReporting.report_from_sms("+260970000000", "REPORT CHOLERA UTH") ==
               {:error, :unregistered_number}

      assert length(Accounts.list_users()) == users_before
      assert CaseManagement.list_cases() == []
    end

    test "refuses a registered number on an account with no role" do
      phone_only_user_fixture("+260970000001")

      assert SmsReporting.report_from_sms("+260970000001", "REPORT CHOLERA") ==
               {:error, :unregistered_number}
    end

    test "refuses an unregistered number before reading the text" do
      assert SmsReporting.report_from_sms("+260970000000", "hello") ==
               {:error, :unregistered_number}
    end

    test "reporter_kind/1 tells USSD what to ask next" do
      facility = facility_fixture()
      reporter(:health_worker, facility, "+260971000001")
      reporter(:district_officer, nil, "+260971000002")

      assert SmsReporting.reporter_kind("+260971000001") == :own_facility
      assert SmsReporting.reporter_kind("+260971000002") == :names_facility
      assert SmsReporting.reporter_kind("+260970000000") == :unregistered
    end
  end

  describe "report_from_sms/2 - a health worker" do
    setup do
      facility = facility_fixture(%{code: "KBW", name: "Kabwata Clinic"})
      worker = reporter(:health_worker, facility, "+260971234567")
      %{facility: facility, worker: worker}
    end

    test "records REPORT <DISEASE> at their own facility, as them", %{
      facility: facility,
      worker: worker
    } do
      assert {:ok, case_record} = SmsReporting.report_from_sms(worker.phone, "REPORT CHOLERA")

      assert case_record.disease == :cholera
      assert case_record.facility_id == facility.id
      assert case_record.reported_by_id == worker.id
      assert case_record.status == :suspected
    end

    test "accepts their own facility code too", %{facility: facility, worker: worker} do
      assert {:ok, case_record} = SmsReporting.report_from_sms(worker.phone, "REPORT MALARIA KBW")
      assert case_record.facility_id == facility.id
    end

    test "refuses another facility's code, as the web form does", %{worker: worker} do
      facility_fixture(%{code: "UTH"})

      assert SmsReporting.report_from_sms(worker.phone, "REPORT CHOLERA UTH") ==
               {:error, {:wrong_facility, "UTH", "KBW"}}

      assert CaseManagement.list_cases() == []
    end

    test "is case-insensitive and tolerates extra whitespace", %{worker: worker} do
      assert {:ok, case_record} =
               SmsReporting.report_from_sms(worker.phone, "  report   cholera  ")

      assert case_record.disease == :cholera
    end

    test "matches the sender's number with surrounding whitespace", %{worker: worker} do
      assert {:ok, _case} = SmsReporting.report_from_sms(" #{worker.phone} ", "REPORT CHOLERA")
    end

    test "accepts COVID as an alias for covid19", %{worker: worker} do
      assert {:ok, case_record} = SmsReporting.report_from_sms(worker.phone, "REPORT COVID")
      assert case_record.disease == :covid19
    end

    test "rejects unparseable text", %{worker: worker} do
      assert SmsReporting.report_from_sms(worker.phone, "hello") == {:error, :unrecognized_format}
    end

    test "rejects an unrecognized disease", %{worker: worker} do
      assert SmsReporting.report_from_sms(worker.phone, "REPORT FLU") ==
               {:error, {:unknown_disease, "FLU"}}
    end

    test "refuses a health worker with no facility" do
      worker = reporter(:health_worker, nil, "+260971999999")

      assert SmsReporting.report_from_sms(worker.phone, "REPORT CHOLERA") ==
               {:error, :no_facility}
    end
  end

  describe "report_from_sms/2 - other roles" do
    setup do
      %{officer: reporter(:district_officer, nil, "+260972222222")}
    end

    test "records a report at the facility named", %{officer: officer} do
      facility = facility_fixture(%{code: "UTH"})

      assert {:ok, case_record} =
               SmsReporting.report_from_sms(officer.phone, "REPORT CHOLERA UTH")

      assert case_record.facility_id == facility.id
      assert case_record.reported_by_id == officer.id
    end

    test "must name a facility", %{officer: officer} do
      assert SmsReporting.report_from_sms(officer.phone, "REPORT CHOLERA") ==
               {:error, :facility_code_required}
    end

    test "rejects an unknown facility code", %{officer: officer} do
      assert SmsReporting.report_from_sms(officer.phone, "REPORT CHOLERA NOPE") ==
               {:error, {:unknown_facility, "NOPE"}}
    end
  end

  describe "confirmation_message/1" do
    test "confirms success, naming the disease and facility" do
      facility = facility_fixture(%{code: "UTH", name: "UTH"})
      worker = reporter(:health_worker, facility, "+260971234567")
      {:ok, case_record} = SmsReporting.report_from_sms(worker.phone, "REPORT CHOLERA")

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

    test "tells an unregistered number how to get registered" do
      message = SmsReporting.confirmation_message({:error, :unregistered_number})
      assert message =~ "isn't registered"
      assert message =~ "MOH administrator"
    end

    test "tells a health worker which facility they can report for" do
      message = SmsReporting.confirmation_message({:error, {:wrong_facility, "UTH", "KBW"}})
      assert message =~ "own facility (KBW)"
      assert message =~ "not UTH"
    end

    test "asks other roles for a facility code" do
      message = SmsReporting.confirmation_message({:error, :facility_code_required})
      assert message =~ "facility code"
    end

    test "explains a missing facility on the account" do
      message = SmsReporting.confirmation_message({:error, :no_facility})
      assert message =~ "no facility"
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
      reporter(:health_worker, facility, "+260977000111")
      name = :"sms_pipeline_test_#{System.unique_integer([:positive])}"
      start_supervised!({Pipeline, name: name})

      log =
        capture_log(fn ->
          Pipeline.push(name, %{from: "+260977000111", text: "REPORT TYPHOID"})

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
      facility = facility_fixture(%{code: "MMH"})
      reporter(:health_worker, facility, "+260977000111")
      name = :"sms_pipeline_test_#{System.unique_integer([:positive])}"
      start_supervised!({Pipeline, name: name})

      log =
        capture_log(fn ->
          Pipeline.push(name, %{from: "+260977000111", text: "not a report"})

          # Follow the bad message with a good one on the same pipeline -
          # this only passes if the pipeline is still alive and taking
          # demand right after rejecting a message, not just that a case
          # never appears.
          Pipeline.push(name, %{from: "+260977000111", text: "REPORT MEASLES"})

          wait_until(fn -> CaseManagement.list_cases() != [] end)
        end)

      assert [case_record] = CaseManagement.list_cases()
      assert case_record.disease == :measles

      # The rejected message's own reply (not the accepted one's).
      assert log =~ "couldn't read that report"
    end
  end

  # A user with `role` (and `facility`, or nil) whose `phone` is
  # registered for SMS reporting.
  defp reporter(role, facility, phone) do
    user_fixture()
    |> set_role(role, facility && facility.id)
    |> set_phone(phone)
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
