defmodule ZamHealthWatchWeb.PageController do
  use ZamHealthWatchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
