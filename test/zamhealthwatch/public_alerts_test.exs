defmodule ZamHealthWatch.PublicAlertsTest do
  # Not async: handle_inbound_sms/2's tests temporarily raise the
  # *global* Logger level to capture SmsGateway.Logger's output, same
  # trade-off (and same reason) AlertWorkerTest already opts out of
  # async for.
  use ZamHealthWatch.DataCase, async: false

  import ExUnit.CaptureLog
  import ZamHealthWatch.PublicAlertsFixtures

  alias ZamHealthWatch.PublicAlerts

  describe "subscribe/1" do
    test "creates a new subscriber" do
      assert {:ok, subscriber} = PublicAlerts.subscribe("+260971234567")
      assert subscriber.phone == "+260971234567"
      assert PublicAlerts.list_subscriber_phones() == ["+260971234567"]
    end

    test "is idempotent - subscribing twice doesn't create a duplicate row" do
      assert {:ok, first} = PublicAlerts.subscribe("+260971234567")
      assert {:ok, second} = PublicAlerts.subscribe("+260971234567")

      assert first.id == second.id
      assert PublicAlerts.list_subscriber_phones() == ["+260971234567"]
    end
  end

  describe "unsubscribe/1" do
    test "removes an existing subscriber" do
      alert_subscriber_fixture(%{phone: "+260971234567"})

      assert :ok = PublicAlerts.unsubscribe("+260971234567")
      assert PublicAlerts.list_subscriber_phones() == []
    end

    test "is a no-op for a number that was never subscribed" do
      assert :ok = PublicAlerts.unsubscribe("+260971234567")
      assert PublicAlerts.list_subscriber_phones() == []
    end
  end

  describe "list_subscriber_phones/0" do
    test "returns every subscribed phone number" do
      alert_subscriber_fixture(%{phone: "+260971111111"})
      alert_subscriber_fixture(%{phone: "+260972222222"})

      assert Enum.sort(PublicAlerts.list_subscriber_phones()) ==
               ["+260971111111", "+260972222222"]
    end

    test "returns an empty list with no subscribers" do
      assert PublicAlerts.list_subscriber_phones() == []
    end
  end

  describe "handle_inbound_sms/2" do
    setup do
      original_level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: original_level) end)
      :ok
    end

    test "SUBSCRIBE subscribes the sender and replies with a confirmation" do
      log =
        capture_log(fn ->
          assert :handled = PublicAlerts.handle_inbound_sms("+260971234567", "SUBSCRIBE")
        end)

      assert PublicAlerts.list_subscriber_phones() == ["+260971234567"]
      assert log =~ "+260971234567"
      assert log =~ "subscribed"
    end

    test "is case-insensitive and tolerates surrounding whitespace" do
      capture_log(fn ->
        assert :handled = PublicAlerts.handle_inbound_sms("+260971234567", "  subscribe  ")
      end)

      assert PublicAlerts.list_subscriber_phones() == ["+260971234567"]
    end

    test "STOP unsubscribes the sender and replies with a confirmation" do
      alert_subscriber_fixture(%{phone: "+260971234567"})

      log =
        capture_log(fn ->
          assert :handled = PublicAlerts.handle_inbound_sms("+260971234567", "STOP")
        end)

      assert PublicAlerts.list_subscriber_phones() == []
      assert log =~ "unsubscribed"
    end

    test "STOP from a number that was never subscribed still replies, without erroring" do
      capture_log(fn ->
        assert :handled = PublicAlerts.handle_inbound_sms("+260971234567", "STOP")
      end)

      assert PublicAlerts.list_subscriber_phones() == []
    end

    test "anything else is not a keyword, and nothing is sent" do
      log =
        capture_log(fn ->
          assert :not_a_keyword =
                   PublicAlerts.handle_inbound_sms("+260971234567", "REPORT CHOLERA UTH")
        end)

      assert PublicAlerts.list_subscriber_phones() == []
      refute log =~ "SMS (mock delivery)"
    end
  end
end
