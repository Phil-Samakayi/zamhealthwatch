defmodule ZamHealthWatchWeb.PageController do
  use ZamHealthWatchWeb, :controller

  alias ZamHealthWatch.Demo

  # The landing page doubles as the demo deployment's front door
  # (Iteration 14): it lists the shared demo logins, read from
  # ZamHealthWatch.Demo so the page and the seeded accounts can never
  # disagree about what the credentials are. When the deployment resets
  # its demo data on boot (Iteration 16), the page says so, so visitors
  # know they can change anything.
  def home(conn, _params) do
    render(conn, :home,
      demo_accounts: Demo.accounts(),
      demo_password: Demo.password(),
      demo_data_resets: Demo.reset_on_boot?()
    )
  end
end
