import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :zamhealthwatch, ZamHealthWatch.Repo,
  username: "postgres",
  password: "Lacas24.",
  hostname: "localhost",
  database: "zamhealthwatch_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "8rcML2vd9GoESQiTD6avGKMANjHAbrTB68opK9VB5unzzd/OOdfmUpIB7CwI5aQZ",
  server: false

# In test we don't send emails
config :zamhealthwatch, ZamHealthWatch.Mailer, adapter: Swoosh.Adapters.Test

# Oban's own recommended test config: jobs are inserted (so
# Oban.Testing.assert_enqueued/2 can see them) but never actually run by a
# queue processor.
config :zamhealthwatch, Oban, testing: :manual

# ZamHealthWatch.PublicAlerts.Subscriber is a permanent, globally-named
# GenServer. Left running during tests, it would react to every case any
# test creates (from any process, any sandboxed connection) and try to
# write an Oban job through a Repo connection it was never allowed into -
# random DBConnection.OwnershipError crashes across the whole async suite,
# not just this feature's own tests. Off by default here; tests that want
# to exercise it start their own instance with start_supervised!/1 and
# explicitly Sandbox.allow/3 it into that one test's connection instead.
config :zamhealthwatch, :start_public_alerts_subscriber, false

# Same reasoning and same fix shape as :start_public_alerts_subscriber
# above: ZamHealthWatch.SmsReporting.Pipeline is a permanent Broadway
# pipeline that would otherwise try to write cases through Repo from
# its own internal processor processes - processes no test ever
# explicitly grants Sandbox access to. Off by default here; tests that
# want to exercise the real pipeline start their own uniquely-named
# instance with start_supervised!/1 and switch that test's Repo Sandbox
# mode to {:shared, self()} (see sms_reporting_test.exs) rather than
# Sandbox.allow/3 - Broadway's processor processes aren't a single
# well-known pid the way PublicAlerts.Subscriber's GenServer is, so
# there's no one pid to allow individually.
config :zamhealthwatch, :start_sms_reporting_pipeline, false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
