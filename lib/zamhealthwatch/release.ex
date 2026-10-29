defmodule ZamHealthWatch.Release do
  @moduledoc """
  Tasks run against a built release, where Mix isn't available - the
  deployed container has no `mix ecto.migrate` or `mix run
  priv/repo/seeds.exs` to call, only `bin/zamhealthwatch eval "..."`.

  `setup/0` is what the Dockerfile's start command runs before booting
  the server: migrate, then seed. Both halves are safe to run on every
  boot - migrations only apply what's pending, and `priv/repo/seeds.exs`
  is idempotent by design (see its own comments) - which matters on
  Render's free plan specifically: the instance spins down when idle and
  boots fresh on the next request, so this runs far more often than a
  one-off deploy step would.

  Kept to the same shape `mix phx.gen.release` generates for `migrate/0`
  and `rollback/2`, so anyone familiar with a stock Phoenix release
  recognises it; `seed/0` and `setup/0` are this project's additions.
  """

  @app :zamhealthwatch

  @doc "Migrates, then seeds. Run before starting the server."
  def setup do
    migrate()
    seed()
  end

  @doc "Runs every pending migration for every repo."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rolls `repo` back to `version`."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc """
  Evaluates `priv/repo/seeds.exs` inside the fully started application.

  Starts the whole app rather than only the Repo (the way `migrate/0`
  does via `Ecto.Migrator.with_repo/2`) because seeding goes through
  the real context functions - `Geography.create_district/1`,
  `CaseManagement.create_case/1`, and so on - and those broadcast over
  `Phoenix.PubSub` on success. With only the Repo started, the first
  broadcast would crash on an unstarted PubSub. The HTTP listener stays
  off during this step: `PHX_SERVER` is only set for the final `start`
  in the Dockerfile's command, not for this `eval`.
  """
  def seed do
    load_app()
    {:ok, _apps} = Application.ensure_all_started(@app)

    @app
    |> Application.app_dir("priv/repo/seeds.exs")
    |> Code.eval_file()

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Managed Postgres hosts (Neon, for this project's deployment)
    # require TLS, so :ssl has to be running before the Repo connects.
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
