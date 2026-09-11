defmodule ZamHealthWatchWeb.MapLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures

  describe "Case map" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/map")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders the empty state when no facility has coordinates", %{conn: conn} do
      facility_fixture(%{code: "NC1"})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/map")

      assert html =~ "Case map"
      assert html =~ "No facilities have a known location yet"
      refute html =~ "id=\"case-map\""
    end

    test "renders the map container when at least one facility has coordinates", %{conn: conn} do
      facility_fixture(%{code: "WC1", latitude: -15.4, longitude: 28.3})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/map")

      assert html =~ "id=\"case-map\""
      refute html =~ "No facilities have a known location yet"
    end
  end
end
