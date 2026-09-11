defmodule ZamHealthWatchWeb.AdminLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.Geography

  # `Accounts.role_changeset/2`/`assign_user_role/2` have existed since
  # Iteration 0 (the migration that added `role`/`facility_id` to `users`
  # landed there too) - what was missing was ever a screen to drive them.
  # A brand-new user has `role: nil` until *something* assigns one
  # (Iteration 0's decision log), and by Iteration 3 that gap was
  # actually biting: role-gated case status transitions shipped with no
  # way to grant a role except a raw `iex -S mix` snippet (logged as an
  # "operational, not a code gotcha" note). This page is that missing
  # something.
  @role_options [
    {"Health worker", :health_worker},
    {"District officer", :district_officer},
    {"MOH admin", :moh_admin}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Manage users
        <:subtitle>
          Assign a role - and, for a health worker, optionally a facility - to every
          registered user. A user with no role assigned can still log in and report
          cases, but can't use anything role-gated yet (see the case list's
          Confirm/Resolve actions).
        </:subtitle>
      </.header>

      <.table id="users" rows={@users} row_id={&"user-#{&1.id}"}>
        <:col :let={user} label="User">{user_label(user)}</:col>
        <:col :let={user} label="Current role">
          <span :if={user.role}>{role_label(user.role)}</span>
          <span :if={is_nil(user.role)} class="text-base-content/50">Unassigned</span>
        </:col>
        <:col :let={user} label="Current facility">
          {Map.get(@facilities_by_id, user.facility_id, "-")}
        </:col>
        <:col :let={user} label="Assign">
          <.form
            for={@forms[user.id]}
            phx-submit="assign_role"
            phx-value-id={user.id}
            class="flex flex-wrap gap-2 items-end"
          >
            <.input
              field={@forms[user.id][:role]}
              type="select"
              options={@role_options}
              prompt="No role"
              class="select select-sm"
            />
            <.input
              field={@forms[user.id][:facility_id]}
              type="select"
              options={@facility_options}
              prompt="No facility"
              class="select select-sm"
            />
            <.button class="btn-sm" phx-disable-with="Saving...">Save</.button>
          </.form>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    facilities = Geography.list_facilities()
    users = Accounts.list_users() |> Enum.sort_by(&user_label/1)

    socket =
      socket
      |> assign(:role_options, @role_options)
      |> assign(:facility_options, Enum.map(facilities, &{&1.name, &1.id}))
      |> assign(:facilities_by_id, Map.new(facilities, &{&1.id, &1.name}))
      |> assign(:users, users)
      |> assign(:forms, Map.new(users, &{&1.id, role_form(&1)}))

    {:ok, socket}
  end

  @impl true
  def handle_event("assign_role", %{"id" => id, "role" => role_params}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.assign_user_role(user, role_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role updated for #{user_label(updated_user)}.")
         |> assign(:users, replace_user(socket.assigns.users, updated_user))
         |> update(:forms, &Map.put(&1, updated_user.id, role_form(updated_user)))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Couldn't update that role - check the form below.")
         |> update(:forms, &Map.put(&1, id, role_form(user, changeset)))}
    end
  end

  defp replace_user(users, %{id: id} = updated_user) do
    Enum.map(users, fn
      %{id: ^id} -> updated_user
      other -> other
    end)
  end

  defp role_form(user, changeset \\ nil) do
    to_form(changeset || Accounts.change_user_role(user), as: "role", id: "role-form-#{user.id}")
  end

  # Same "email if present, else phone, else a placeholder" identity
  # rule `CaseLive.Index.reporter_label/1` already established for
  # attributing a case to whoever reported it - a user here is
  # identified the same way, for the same reason (an SMS-only reporter
  # has no email).
  defp user_label(%{email: email}) when is_binary(email), do: email
  defp user_label(%{phone: phone}) when is_binary(phone), do: phone
  defp user_label(_user), do: "Unknown user"

  # Same "look the display label up in the options list rather than call
  # `Phoenix.Naming.humanize/1` directly" move `CaseLive.Index.disease_label/1`
  # already makes, and for the same reason - humanize's one-capital-letter,
  # underscore-to-space rule renders `:moh_admin` as "Moh admin", not the
  # acronym-cased "MOH admin" @role_options actually wants everywhere this
  # role's name is shown, not just in the dropdown.
  defp role_label(role) do
    Enum.find_value(@role_options, Phoenix.Naming.humanize(role), fn {label, value} ->
      value == role && label
    end)
  end
end
