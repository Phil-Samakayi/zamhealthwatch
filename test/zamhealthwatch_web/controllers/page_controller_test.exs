defmodule ZamHealthWatchWeb.PageControllerTest do
  use ZamHealthWatchWeb.ConnCase

  import ZamHealthWatch.AccountsFixtures

  alias ZamHealthWatch.Demo

  describe "GET /" do
    setup :restore_reset_flag

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

    test "says the demo data resets when the deployment resets it on boot", %{conn: conn} do
      Application.put_env(:zamhealthwatch, :demo_reset_on_boot, true)

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="demo-reset-notice")
      assert html =~ "feel free to change anything"
    end

    test "doesn't mention a data reset when the deployment doesn't do one", %{conn: conn} do
      Application.put_env(:zamhealthwatch, :demo_reset_on_boot, false)

      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ ~s(id="demo-reset-notice")
    end
  end

  # Same helper as DemoTest's: the flag is global application config, so
  # put back whatever config/runtime.exs set. This module isn't async.
  defp restore_reset_flag(_context) do
    original = Application.fetch_env(:zamhealthwatch, :demo_reset_on_boot)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:zamhealthwatch, :demo_reset_on_boot, value)
        :error -> Application.delete_env(:zamhealthwatch, :demo_reset_on_boot)
      end
    end)
  end
end
