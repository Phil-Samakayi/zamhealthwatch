defmodule ZamHealthWatch.Repo do
  use Ecto.Repo,
    otp_app: :zamhealthwatch,
    adapter: Ecto.Adapters.Postgres
end
