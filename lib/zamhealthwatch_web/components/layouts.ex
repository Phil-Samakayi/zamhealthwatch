defmodule ZamHealthWatchWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ZamHealthWatchWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar items-start gap-4 px-4 sm:px-6 lg:px-8 border-b border-base-300">
      <div class="flex-1 flex flex-wrap items-center gap-x-4 gap-y-2">
        <a href={~p"/"} class="flex items-center gap-2 font-semibold">
          <.icon name="hero-heart" class="size-5 text-primary" /> ZamHealthWatch
        </a>
        <nav :if={@current_scope && @current_scope.user} id="main-nav" class="flex flex-wrap gap-1">
          <.link :for={{label, path} <- nav_links(@current_scope.user)} href={path} class="btn btn-ghost btn-sm">
            {label}
          </.link>
        </nav>
      </div>
      <div class="flex-none">
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # The app's own navigation (Iteration 14 - before deployment every
  # screen was only reachable by typing its URL, and this header still
  # carried the Phoenix generator's default links). Plain `href`s rather
  # than `navigate`: the screens span three live_sessions plus the
  # controller-rendered home page, and a cross-session `navigate` falls
  # back to a full page load anyway. The two MOH-admin screens are only
  # listed for MOH admins - the router's :require_moh_admin gate is what
  # actually enforces that, hiding the links just avoids offering a
  # dead end.
  @nav_links [
    {"Portal", "/portal"},
    {"Cases", "/cases"},
    {"Labs", "/labs"},
    {"Vaccinations", "/vaccinations"},
    {"Drugs", "/drugs"},
    {"Hospitals", "/hospitals"},
    {"Epidemiology", "/epidemiology"},
    {"Map", "/map"},
    {"Risk", "/risk"},
    {"Guidance", "/guidance"}
  ]

  @admin_nav_links [
    {"National report", "/reports/national"},
    {"Users", "/admin/users"}
  ]

  defp nav_links(%{role: :moh_admin}), do: @nav_links ++ @admin_nav_links
  defp nav_links(_user), do: @nav_links

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
