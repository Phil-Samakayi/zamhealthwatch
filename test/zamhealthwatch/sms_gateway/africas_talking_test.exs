defmodule ZamHealthWatch.SmsGateway.AfricasTalkingTest do
  # Safe to run async: Req.Test.stub/2 registers its stub against this
  # test's own process, and send_sms/2 below runs entirely within that
  # same process (no spawned Task) - no shared, cross-test state.
  use ExUnit.Case, async: true

  alias ZamHealthWatch.SmsGateway.AfricasTalking

  setup do
    Application.put_env(:zamhealthwatch, AfricasTalking, username: "sandbox", api_key: "fake-key")
    on_exit(fn -> Application.delete_env(:zamhealthwatch, AfricasTalking) end)
    :ok
  end

  test "returns :ok for a successful send" do
    Req.Test.stub(AfricasTalking, fn conn ->
      Req.Test.json(conn, %{
        "SMSMessageData" => %{
          "Message" => "Sent",
          "Recipients" => [
            %{"number" => "+260971234567", "status" => "Success", "statusCode" => 101}
          ]
        }
      })
    end)

    assert :ok = AfricasTalking.send_sms("+260971234567", "hello")
  end

  test "returns an error when Africa's Talking rejects the recipient" do
    Req.Test.stub(AfricasTalking, fn conn ->
      Req.Test.json(conn, %{
        "SMSMessageData" => %{
          "Message" => "InvalidPhoneNumber",
          "Recipients" => [
            %{"number" => "+260971234567", "status" => "InvalidPhoneNumber", "statusCode" => 400}
          ]
        }
      })
    end)

    assert {:error, {:unexpected_response, 200, body}} =
             AfricasTalking.send_sms("+260971234567", "hello")

    assert body["SMSMessageData"]["Recipients"] |> hd() |> Map.get("status") ==
             "InvalidPhoneNumber"
  end

  test "returns an error for a non-2xx response" do
    Req.Test.stub(AfricasTalking, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"error" => "invalid api key"})
    end)

    assert {:error, {:unexpected_response, 401, _body}} =
             AfricasTalking.send_sms("+260971234567", "hello")
  end

  describe "which endpoint it calls (Iteration 22)" do
    test "the sandbox username goes to the sandbox endpoint" do
      assert_host("sandbox", nil, "api.sandbox.africastalking.com")
    end

    test "any other username goes to the live endpoint" do
      assert_host("zamhealthwatch", nil, "api.africastalking.com")
    end

    test "a configured base URL overrides both" do
      assert_host("sandbox", "https://sms.example.test", "sms.example.test")
    end
  end

  # Sends one SMS with `username` (and `base_url`, if given) configured,
  # and asserts the request went to `expected_host`. Req.Test runs the
  # stub in this test's own process, so it can message the test directly.
  defp assert_host(username, base_url, expected_host) do
    config = [username: username, api_key: "fake-key"]
    config = if base_url, do: Keyword.put(config, :base_url, base_url), else: config
    Application.put_env(:zamhealthwatch, AfricasTalking, config)
    test_pid = self()

    Req.Test.stub(AfricasTalking, fn conn ->
      send(test_pid, {:host, conn.host, conn.request_path})

      Req.Test.json(conn, %{
        "SMSMessageData" => %{
          "Recipients" => [%{"number" => "+260971234567", "status" => "Success"}]
        }
      })
    end)

    assert :ok = AfricasTalking.send_sms("+260971234567", "hello")
    assert_received {:host, ^expected_host, "/version1/messaging"}
  end

  test "raises when username/api_key aren't configured" do
    Application.delete_env(:zamhealthwatch, AfricasTalking)

    assert_raise KeyError, fn ->
      AfricasTalking.send_sms("+260971234567", "hello")
    end
  end
end
