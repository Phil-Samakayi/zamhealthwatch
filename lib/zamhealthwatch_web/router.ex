defmodule ZamHealthWatchWeb.Router do
  use ZamHealthWatchWeb, :router

  import ZamHealthWatchWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ZamHealthWatchWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Inbound SMS/USSD webhooks - no browser session, no CSRF token to
  # check (a webhook provider isn't a browser), so this deliberately
  # doesn't go through the :browser pipeline.
  scope "/webhooks", ZamHealthWatchWeb do
    pipe_through :api

    post "/sms", SmsWebhookController, :create
  end

  scope "/", ZamHealthWatchWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", ZamHealthWatchWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:zamhealthwatch, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ZamHealthWatchWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ZamHealthWatchWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ZamHealthWatchWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Case reporting requires a logged-in user (reported_by_id is always
      # the current user - see CaseLive.Index), so it belongs in this same
      # live_session rather than a new one (AGENTS.md: never duplicate
      # live_session names).
      live "/cases", CaseLive.Index, :index

      # The epidemiology dashboard is an internal aggregate view of the
      # same case data - no separate public-facing route/auth model exists
      # yet (that's what the Public Alerts subscriber's SMS/mock delivery
      # is for), so for this iteration it sits behind login too, in the
      # same live_session as everything else that requires one.
      live "/epidemiology", EpidemiologyLive.Index, :index

      # Same reasoning as /epidemiology above - an internal view over
      # the same case data, no separate public route/auth model yet.
      live "/map", MapLive.Index, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ZamHealthWatchWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ZamHealthWatchWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
