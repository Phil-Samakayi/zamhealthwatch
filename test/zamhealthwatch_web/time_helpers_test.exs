defmodule ZamHealthWatchWeb.TimeHelpersTest do
  use ExUnit.Case, async: true

  alias ZamHealthWatchWeb.TimeHelpers

  describe "time_ago/1" do
    test "returns 'just now' for a time under a minute ago" do
      assert TimeHelpers.time_ago(DateTime.utc_now()) == "just now"
    end

    test "returns minutes ago" do
      datetime = DateTime.add(DateTime.utc_now(), -125, :second)
      assert TimeHelpers.time_ago(datetime) == "2m ago"
    end

    test "returns hours ago" do
      datetime = DateTime.add(DateTime.utc_now(), -7300, :second)
      assert TimeHelpers.time_ago(datetime) == "2h ago"
    end

    test "returns days ago" do
      datetime = DateTime.add(DateTime.utc_now(), -172_800, :second)
      assert TimeHelpers.time_ago(datetime) == "2d ago"
    end
  end
end
