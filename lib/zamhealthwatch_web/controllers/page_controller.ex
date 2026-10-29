defmodule ZamHealthWatchWeb.PageController do
  use ZamHealthWatchWeb, :controller

  alias ZamHealthWatch.Demo

  # The landing page doubles as the demo deployment's front door
  # (Iteration 14): it lists the shared demo logins, read from
  # ZamHealthWatch.Demo so the page and the seeded accounts can never
  # disagree about what the credentials are.
  def home(conn, _params) do
    render(conn, :home, demo_accounts: Demo.accounts(), demo_password: Demo.password())
  end
end
