defmodule ZamHealthWatchWeb.PageControllerTest do
  use ZamHealthWatchWeb.ConnCase

  import ZamHealthWatch.AccountsFixtures

  alias ZamHealthWatch.Demo

  describe "GET /" do
    test "lists every demo account and the shared password when logged out", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "ZamHealthWatch"
      assert html =~ Demo.password()

      for account <- Demo.accounts() do
        assert html =~ account.email
      end
    end

    test "greets a logged-in user instead of listing demo accounts", %{conn: conn} do
      user = user_fixture()
      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ "logged in as"
      refute html =~ Demo.password()
    end

    test "shows the main navigation only to a logged-in user", %{conn: conn} do
      logged_out = conn |> get(~p"/") |> html_response(200)
      refute logged_out =~ ~s(id="main-nav")

      logged_in = conn |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)
      assert logged_in =~ ~s(id="main-nav")
      refute logged_in =~ "National report"
    end

    test "adds the MOH-admin screens to the navigation for an MOH admin", %{conn: conn} do
      admin = user_fixture() |> set_role(:moh_admin)
      html = conn |> log_in_user(admin) |> get(~p"/") |> html_response(200)

      assert html =~ "National report"
      assert html =~ ~p"/admin/users"
    end
  end
end
