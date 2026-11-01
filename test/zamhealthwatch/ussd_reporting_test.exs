defmodule ZamHealthWatch.UssdReportingTest do
  use ZamHealthWatch.DataCase, async: true

  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.PublicAlerts
  alias ZamHealthWatch.UssdReporting

  @phone "+260979100001"

  describe "handle_session/2 - main menu" do
    test "an empty text (first request of a session) shows the main menu" do
      assert {:continue, menu} = UssdReporting.handle_session(@phone, "")
      assert menu =~ "Report a case"
      assert menu =~ "Subscribe"
      assert menu =~ "Unsubscribe"
    end

    test "an unrecognized top-level choice ends the session" do
      assert {:end, "Invalid selection. Please try again."} =
               UssdReporting.handle_session(@phone, "9")
    end
  end

  describe "handle_session/2 - report a case (option 1)" do
    test "an unregistered number is told straight away that it can't report" do
      assert {:end, message} = UssdReporting.handle_session(@phone, "1")
      assert message =~ "isn't registered"
    end

    test "choosing 1 shows the disease menu to a registered reporter" do
      reporter(:health_worker, facility_fixture(), @phone)

      assert {:continue, menu} = UssdReporting.handle_session(@phone, "1")
      assert menu =~ "Cholera"
      assert menu =~ "Malaria"
      assert menu =~ "Typhoid"
      assert menu =~ "COVID-19"
      assert menu =~ "Measles"
    end

    test "a health worker's report goes straight to their own facility, with no code to type" do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      worker = reporter(:health_worker, facility, @phone)

      assert {:end, message} = UssdReporting.handle_session(@phone, "1*2")

      assert message =~ "Malaria"
      assert message =~ "Kabwata Clinic"

      assert [case_record] = CaseManagement.list_cases()
      assert case_record.disease == :malaria
      assert case_record.facility_id == facility.id
      assert case_record.reported_by_id == worker.id
    end

    test "a district officer is asked for a facility code, and the report lands there" do
      facility = facility_fixture(%{code: "UTH"})
      reporter(:district_officer, nil, @phone)

      assert {:continue, "Enter facility code" <> _} = UssdReporting.handle_session(@phone, "1*2")
      assert {:end, message} = UssdReporting.handle_session(@phone, "1*2*UTH")

      assert message =~ "Malaria"
      assert [case_record] = CaseManagement.list_cases()
      assert case_record.facility_id == facility.id
      assert case_record.status == :suspected
    end

    test "choosing an invalid disease digit ends the session" do
      reporter(:district_officer, nil, @phone)

      assert {:end, "Invalid selection. Please try again."} =
               UssdReporting.handle_session(@phone, "1*9")
    end

    test "an unknown facility code ends the session with the same rejection reply SMS reporting uses" do
      reporter(:district_officer, nil, @phone)

      assert {:end, message} = UssdReporting.handle_session(@phone, "1*1*NOPE")

      assert message =~ "NOPE"
      assert CaseManagement.list_cases() == []
    end

    test "an unregistered number can't report even by sending the full path at once" do
      facility_fixture(%{code: "UTH"})

      assert {:end, message} = UssdReporting.handle_session(@phone, "1*2*UTH")
      assert message =~ "isn't registered"
      assert CaseManagement.list_cases() == []
    end

    test "trailing extra input after a complete report path ends the session as invalid" do
      facility_fixture(%{code: "UTH"})
      reporter(:district_officer, nil, @phone)

      assert {:end, "Invalid selection. Please try again."} =
               UssdReporting.handle_session(@phone, "1*2*UTH*4")

      assert CaseManagement.list_cases() == []
    end
  end

  describe "handle_session/2 - subscribe (option 2)" do
    test "subscribes the phone number and ends the session" do
      assert {:end, message} = UssdReporting.handle_session(@phone, "2")

      assert message =~ "subscribed"
      assert PublicAlerts.list_subscriber_phones() == [@phone]
    end

    test "is idempotent, same as the SMS SUBSCRIBE keyword" do
      UssdReporting.handle_session(@phone, "2")
      UssdReporting.handle_session(@phone, "2")

      assert PublicAlerts.list_subscriber_phones() == [@phone]
    end
  end

  describe "handle_session/2 - unsubscribe (option 3)" do
    test "unsubscribes the phone number and ends the session" do
      {:ok, _subscriber} = PublicAlerts.subscribe(@phone)

      assert {:end, message} = UssdReporting.handle_session(@phone, "3")

      assert message =~ "unsubscribed"
      assert PublicAlerts.list_subscriber_phones() == []
    end

    test "is a no-op, without erroring, for a number that was never subscribed" do
      assert {:end, _message} = UssdReporting.handle_session(@phone, "3")
      assert PublicAlerts.list_subscriber_phones() == []
    end
  end

  # A user with `role` (and `facility`, or nil) whose `phone` is
  # registered for SMS/USSD reporting.
  defp reporter(role, facility, phone) do
    user_fixture()
    |> set_role(role, facility && facility.id)
    |> set_phone(phone)
  end
end
