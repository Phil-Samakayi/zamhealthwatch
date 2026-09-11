defmodule ZamHealthWatchWeb.AdminLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures

  alias ZamHealthWatch.Accounts

  describe "access control" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/users")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects to \"/\" for a logged-in user with no role", %{conn: conn} do
      assert {:error, redirect} =
               conn
               |> log_in_user(user_fixture())
               |> live(~p"/admin/users")

      assert {:redirect, %{to: "/", flash: flash}} = redirect
      assert %{"error" => "You don't have permission to access this page."} = flash
    end

    test "redirects to \"/\" for a logged-in user with a non-admin role", %{conn: conn} do
      user = user_fixture() |> set_role(:health_worker)

      assert {:error, redirect} =
               conn
               |> log_in_user(user)
               |> live(~p"/admin/users")

      assert {:redirect, %{to: "/", flash: flash}} = redirect
      assert %{"error" => "You don't have permission to access this page."} = flash
    end
  end

  describe "listing users" do
    setup %{conn: conn} do
      admin = user_fixture() |> set_role(:moh_admin)
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "shows a web-registered user by email", %{conn: conn} do
      user = user_fixture()
      {:ok, _lv, html} = live(conn, ~p"/admin/users")

      assert html =~ user.email
    end

    test "shows an SMS-only user by phone, not by placeholder text", %{conn: conn} do
      {:ok, _reporter} = Accounts.find_or_create_sms_reporter("+260971234567")
      {:ok, _lv, html} = live(conn, ~p"/admin/users")

      assert html =~ "+260971234567"
      refute html =~ "Unknown user"
    end

    test "shows \"Unassigned\" for a user with no role", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      assert has_element?(lv, row_selector(user), "Unassigned")
    end

    test "shows the current role for a user who already has one", %{conn: conn} do
      user = user_fixture() |> set_role(:district_officer)
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      assert has_element?(lv, row_selector(user), "District officer")
      refute has_element?(lv, row_selector(user), "Unassigned")
    end

    test "shows the current facility, or a dash when none is assigned", %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      with_facility = user_fixture() |> set_role(:health_worker, facility.id)
      without_facility = user_fixture() |> set_role(:health_worker)

      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      assert has_element?(lv, row_selector(with_facility), "Test Clinic")
      assert has_element?(lv, row_selector(without_facility), "-")
    end
  end

  describe "assigning a role" do
    setup %{conn: conn} do
      admin = user_fixture() |> set_role(:moh_admin)
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "assigns a role to a user with none yet", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      result =
        lv
        |> form(role_form_selector(user), %{"role" => %{"role" => "health_worker"}})
        |> render_submit()

      assert result =~ "Role updated for #{user.email}."
      assert has_element?(lv, row_selector(user), "Health worker")
      assert Accounts.get_user!(user.id).role == :health_worker
    end

    test "assigns a role and a facility together", %{conn: conn} do
      facility = facility_fixture(%{name: "Test Clinic"})
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      lv
      |> form(role_form_selector(user), %{
        "role" => %{"role" => "health_worker", "facility_id" => facility.id}
      })
      |> render_submit()

      assert has_element?(lv, row_selector(user), "Test Clinic")
      updated = Accounts.get_user!(user.id)
      assert updated.role == :health_worker
      assert updated.facility_id == facility.id
    end

    test "changes an already-assigned user's role", %{conn: conn} do
      user = user_fixture() |> set_role(:health_worker)
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      lv
      |> form(role_form_selector(user), %{"role" => %{"role" => "moh_admin"}})
      |> render_submit()

      assert has_element?(lv, row_selector(user), "MOH admin")
      assert Accounts.get_user!(user.id).role == :moh_admin
    end

    test "rejects clearing an already-assigned user's role and leaves it unchanged", %{
      conn: conn
    } do
      user = user_fixture() |> set_role(:health_worker)
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      result =
        lv
        |> form(role_form_selector(user), %{"role" => %{"role" => ""}})
        |> render_submit()

      assert result =~ "Couldn&#39;t update that role"
      assert Accounts.get_user!(user.id).role == :health_worker
    end
  end

  # Scopes an assertion to one user's own table row (`row_id` passed
  # explicitly to `<.table>` in `AdminLive.Index`, since the default
  # `stream/3`-derived id only applies when `rows` is a LiveStream - this
  # page's `@users` is a plain list, recomputed on every mutation rather
  # than streamed, since nothing else needs to react live to a role
  # change yet). Not strictly needed for PubSub-leakage reasons the way
  # `CaseLive.IndexTest`'s `row_selector/1` is (this page has no PubSub
  # subscription), but every other row-scoped assertion in this project
  # already follows this pattern, and a page listing every user is
  # exactly the kind of table where an unscoped text match could
  # coincidentally hit a different row.
  defp row_selector(%{id: id}), do: "#user-#{id}"

  # `to_form/2`'s explicit `id: "role-form-#{user.id}"` (set in
  # `AdminLive.Index.role_form/2`) is what makes each row's form
  # independently selectable here.
  defp role_form_selector(%{id: id}), do: "#role-form-#{id}"
end
