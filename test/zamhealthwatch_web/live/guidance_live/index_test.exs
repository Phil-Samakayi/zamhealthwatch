defmodule ZamHealthWatchWeb.GuidanceLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures

  describe "Guidance" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/guidance")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "lists every tracked disease, with none selected by default", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/guidance")

      assert html =~ "Cholera"
      assert html =~ "Malaria"
      assert html =~ "Typhoid"
      assert html =~ "COVID-19"
      assert html =~ "Measles"
      assert html =~ "Select a disease above to see its guidance."
    end

    test "selecting a disease shows its guidance", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/guidance")

      html =
        lv
        |> element("a", "Cholera")
        |> render_click()

      assert html =~ "acute watery diarrhoea"
      assert html =~ "Immediately notifiable"
      refute html =~ "Select a disease above to see its guidance."
    end

    test "navigating straight to a disease URL shows that disease's guidance", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/guidance/malaria")

      assert html =~ "rapid diagnostic test"
    end

    test "an unrecognized disease in the URL falls back to no selection, without crashing", %{
      conn: conn
    } do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/guidance/not-a-real-disease")

      assert html =~ "Select a disease above to see its guidance."
    end
  end
end
