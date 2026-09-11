defmodule ZamHealthWatch.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ZamHealthWatchWeb.Telemetry,
        ZamHealthWatch.Repo,
        {DNSCluster, query: Application.get_env(:zamhealthwatch, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ZamHealthWatch.PubSub},
        {Oban, Application.fetch_env!(:zamhealthwatch, Oban)}
      ] ++
        public_alerts_children() ++
        sms_reporting_children() ++
        [
          # Start to serve requests, typically the last entry
          ZamHealthWatchWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZamHealthWatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Off in test - see the config/test.exs comment on
  # :start_public_alerts_subscriber for why.
  defp public_alerts_children do
    if Application.get_env(:zamhealthwatch, :start_public_alerts_subscriber, true) do
      [ZamHealthWatch.PublicAlerts.Subscriber]
    else
      []
    end
  end

  # Off in test - same Ecto Sandbox risk as PublicAlerts.Subscriber above
  # (a permanent process writing through Repo from outside any test's own
  # process/connection). See config/test.exs's comment on
  # :start_sms_reporting_pipeline.
  defp sms_reporting_children do
    if Application.get_env(:zamhealthwatch, :start_sms_reporting_pipeline, true) do
      [ZamHealthWatch.SmsReporting.Pipeline]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ZamHealthWatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
