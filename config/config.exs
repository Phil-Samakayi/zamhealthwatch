# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :zamhealthwatch, :scopes,
  user: [
    default: true,
    module: ZamHealthWatch.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: ZamHealthWatch.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :zamhealthwatch,
  namespace: ZamHealthWatch,
  ecto_repos: [ZamHealthWatch.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ZamHealthWatchWeb.ErrorHTML, json: ZamHealthWatchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ZamHealthWatch.PubSub,
  live_view: [signing_salt: "4HkNO3ek"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :zamhealthwatch, ZamHealthWatch.Mailer, adapter: Swoosh.Adapters.Local

# Configure Oban - runs the Public Alerts delivery queue (see
# ZamHealthWatch.PublicAlerts). One queue is enough for now; split it up
# if/when a second kind of background job needs its own concurrency limit.
config :zamhealthwatch, Oban,
  repo: ZamHealthWatch.Repo,
  plugins: [{Oban.Plugins.Pruner, max_age: :timer.hours(24 * 7)}],
  queues: [alerts: 10]

# Whether ZamHealthWatch.PublicAlerts.Subscriber starts automatically with
# the app. On in dev/prod; off in test - see config/test.exs for why.
config :zamhealthwatch, :start_public_alerts_subscriber, true

# Whether ZamHealthWatch.SmsReporting.Pipeline (the Broadway pipeline
# consuming inbound SMS reports) starts automatically with the app. On in
# dev/prod; off in test - see config/test.exs for why.
config :zamhealthwatch, :start_sms_reporting_pipeline, true

# The default SmsGateway implementation - logs instead of actually
# sending. Overridden to ZamHealthWatch.SmsGateway.AfricasTalking only
# in config/runtime.exs's prod block, and only when real Africa's
# Talking credentials are present in the environment. Left as the
# Logger stand-in in :dev and :test - see SmsGateway's own moduledoc.
config :zamhealthwatch, :sms_gateway, ZamHealthWatch.SmsGateway.Logger

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  zamhealthwatch: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  zamhealthwatch: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
