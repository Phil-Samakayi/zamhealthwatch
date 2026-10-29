defmodule ZamHealthWatchWeb.UssdWebhookControllerTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import ZamHealthWatch.GeographyFixtures

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.PublicAlerts

  describe "POST /webhooks/ussd" do
    test "an empty text continues the session with the main menu", %{conn: conn} do
      conn =
        post(conn, ~p"/webhooks/ussd", %{
          "sessionId" => "sess-1",
          "serviceCode" => "*384#",
          "phoneNumber" => "+260971234567",
          "text" => ""
        })

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert response(conn, 200) =~ ~r/^CON Welcome to ZamHealthWatch/
    end

    test "a full report path ends the session and creates a real case", %{conn: conn} do
      facility = facility_fixture(%{code: "UTH"})

      conn =
        post(conn, ~p"/webhooks/ussd", %{
          "sessionId" => "sess-2",
          "serviceCode" => "*384#",
          "phoneNumber" => "+260971234567",
          "text" => "1*1*UTH"
        })

      assert conn.status == 200
      body = response(conn, 200)
      assert body =~ ~r/^END /
      assert body =~ "Cholera"

      assert [case_record] = CaseManagement.list_cases()
      assert case_record.disease == :cholera
      assert case_record.facility_id == facility.id
    end

    test "option 2 subscribes the phone number and ends the session", %{conn: conn} do
      conn =
        post(conn, ~p"/webhooks/ussd", %{
          "sessionId" => "sess-3",
          "serviceCode" => "*384#",
          "phoneNumber" => "+260971234567",
          "text" => "2"
        })

      assert conn.status == 200
      assert response(conn, 200) =~ ~r/^END .*subscribed/

      assert PublicAlerts.list_subscriber_phones() == ["+260971234567"]
    end

    test "responds 200 with an END message even for a payload missing phoneNumber/text", %{
      conn: conn
    } do
      conn = post(conn, ~p"/webhooks/ussd", %{"sessionId" => "sess-4", "serviceCode" => "*384#"})

      assert conn.status == 200
      assert response(conn, 200) =~ ~r/^END /
    end
  end
end
