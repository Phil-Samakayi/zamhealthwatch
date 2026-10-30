import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/zamhealthwatch start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :zamhealthwatch, ZamHealthWatchWeb.Endpoint, server: true
end

config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Public demo only (Iteration 16): wipe and reseed demo activity every
# time priv/repo/seeds.exs runs, which on the deployed app is every boot.
# See ZamHealthWatch.Demo.reset_activity!/0. Never set this on a
# deployment holding real data.
config :zamhealthwatch, :demo_reset_on_boot, System.get_env("DEMO_RESET_ON_BOOT") == "true"

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/zamhealthwatch_web/router\.ex$"E,
        ~r"lib/zamhealthwatch_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Neon (this project's hosted Postgres - see docs/ITERATIONS.md,
  # Iteration 14) hands out connection strings ending in
  # `?sslmode=require&channel_binding=require`. Those are libpq options;
  # Ecto would turn them into unknown Repo options instead, so the query
  # string is dropped here and TLS is configured explicitly below.
  database_url = database_url |> URI.parse() |> Map.put(:query, nil) |> URI.to_string()

  # TLS with full certificate and hostname verification, on when
  # DATABASE_SSL is set. `server_name_indication` matters for Neon: it
  # routes each connection to the right database by the SNI hostname,
  # and Postgrex upgrades an already-open TCP socket to TLS, so it can't
  # infer that name by itself.
  database_ssl =
    if System.get_env("DATABASE_SSL") in ~w(true 1) do
      db_host = database_url |> URI.parse() |> Map.fetch!(:host) |> String.to_charlist()

      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: db_host,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      false
    end

  config :zamhealthwatch, ZamHealthWatch.Repo,
    ssl: database_ssl,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Render sets RENDER_EXTERNAL_HOSTNAME (e.g. zamhealthwatch.onrender.com)
  # on every web service, so PHX_HOST only needs setting by hand for a
  # custom domain. The endpoint's host also drives LiveView's websocket
  # origin check, so a wrong value here shows up as LiveViews refusing
  # to connect.
  host =
    System.get_env("PHX_HOST") || System.get_env("RENDER_EXTERNAL_HOSTNAME") || "example.com"

  # No email provider is connected for the demo deployment (Iteration
  # 14 - visitors log in with the published demo accounts instead). The
  # Local adapter config.exs sets can't run in prod: prod.exs turns off
  # its in-memory storage, so the first magic-link request would crash.
  # The Logger adapter writes each email to the server log instead -
  # private to whoever owns the Render service, which also means the
  # owner can still sign in with their own address by copying the link
  # out of the logs.
  config :zamhealthwatch, ZamHealthWatch.Mailer,
    adapter: Swoosh.Adapters.Logger,
    log_full_email: true

  config :zamhealthwatch, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Real Africa's Talking SMS delivery, only when both credentials are
  # present - unlike DATABASE_URL/SECRET_KEY_BASE above, a missing SMS
  # provider doesn't `raise` here. SMS/USSD alerts and reply confirmations
  # are a real but non-essential feature of this app (see
  # ZamHealthWatch.SmsGateway.AfricasTalking's own moduledoc for the
  # reasoning) - it's better for the app to boot in a degraded,
  # log-only-delivery state than to refuse to start entirely over a
  # missing SMS API key.
  at_username = System.get_env("AFRICAS_TALKING_USERNAME")
  at_api_key = System.get_env("AFRICAS_TALKING_API_KEY")

  if at_username && at_api_key do
    config :zamhealthwatch, :sms_gateway, ZamHealthWatch.SmsGateway.AfricasTalking

    config :zamhealthwatch, ZamHealthWatch.SmsGateway.AfricasTalking,
      username: at_username,
      api_key: at_api_key,
      sender_id: System.get_env("AFRICAS_TALKING_SENDER_ID")
  else
    require Logger

    Logger.warning(
      "AFRICAS_TALKING_USERNAME/AFRICAS_TALKING_API_KEY not set - " <>
        "public alerts and SMS report replies will only be logged, not actually sent."
    )
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :zamhealthwatch, ZamHealthWatchWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :zamhealthwatch, ZamHealthWatch.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
