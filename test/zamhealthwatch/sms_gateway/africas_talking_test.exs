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

  test "raises when username/api_key aren't configured" do
    Application.delete_env(:zamhealthwatch, AfricasTalking)

    assert_raise KeyError, fn ->
      AfricasTalking.send_sms("+260971234567", "hello")
    end
  end
end
