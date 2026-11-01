defmodule ZamHealthWatchWeb.WebhookTokenTest do
  # Not async: the token is global application config, changed for the
  # span of each test.
  use ZamHealthWatchWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias ZamHealthWatch.PublicAlerts

  @token "3f9a1c0e8b7d4a6f2e5c9b1a0d8e7f6c"

  setup do
    original = Application.fetch_env(:zamhealthwatch, :webhook_token)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:zamhealthwatch, :webhook_token, value)
        :error -> Application.delete_env(:zamhealthwatch, :webhook_token)
      end
    end)
  end

  describe "with a token configured" do
    setup do
      Application.put_env(:zamhealthwatch, :webhook_token, @token)
    end

    test "accepts an SMS webhook carrying the right token", %{conn: conn} do
      conn = post(conn, "/webhooks/sms?token=#{@token}", subscribe("+260979500001"))

      assert conn.status == 200
      assert "+260979500001" in PublicAlerts.list_subscriber_phones()
    end

    test "refuses an SMS webhook with no token, doing nothing", %{conn: conn} do
      conn = post(conn, "/webhooks/sms", subscribe("+260979500002"))

      assert conn.status == 403
      refute "+260979500002" in PublicAlerts.list_subscriber_phones()
    end

    test "refuses an SMS webhook with the wrong token", %{conn: conn} do
      conn = post(conn, "/webhooks/sms?token=wrong", subscribe("+260979500003"))

      assert conn.status == 403
      refute "+260979500003" in PublicAlerts.list_subscriber_phones()
    end

    test "ignores a token sent in the form body instead of the URL", %{conn: conn} do
      params = Map.put(subscribe("+260979500004"), "token", @token)
      conn = post(conn, "/webhooks/sms", params)

      assert conn.status == 403
    end

    test "guards the USSD webhook too", %{conn: conn} do
      params = %{"sessionId" => "s1", "phoneNumber" => "+260979500005", "text" => ""}

      assert conn |> post("/webhooks/ussd", params) |> Map.fetch!(:status) == 403

      assert build_conn()
             |> post("/webhooks/ussd?token=#{@token}", params)
             |> response(200) =~ "CON "
    end
  end

  test "refuses every webhook when production has no token set", %{conn: conn} do
    Application.put_env(:zamhealthwatch, :webhook_token, :missing)

    log =
      capture_log(fn ->
        conn = post(conn, "/webhooks/sms?token=anything", subscribe("+260979500006"))
        assert conn.status == 403
      end)

    assert log =~ "WEBHOOK_TOKEN isn't set"
    refute "+260979500006" in PublicAlerts.list_subscriber_phones()
  end

  test "lets webhooks through when no token is configured (development and tests)", %{
    conn: conn
  } do
    Application.delete_env(:zamhealthwatch, :webhook_token)

    conn = post(conn, "/webhooks/sms", subscribe("+260979500007"))

    assert conn.status == 200
  end

  defp subscribe(phone), do: %{"from" => phone, "text" => "SUBSCRIBE"}
end
