defmodule ZamHealthWatchWeb.HealthControllerTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  test "GET /health returns a plain 200", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end
end
