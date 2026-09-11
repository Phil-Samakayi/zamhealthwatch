defmodule ZamHealthWatch.PublicAlertsFixtures do
  @moduledoc """
  This module defines test helpers for creating entities via the
  `ZamHealthWatch.PublicAlerts` context.
  """

  @doc """
  Generate an alert subscriber, going straight through
  `PublicAlerts.subscribe/1` rather than inserting the schema directly -
  same "exercise the real context function, not just the schema" call
  every other fixture module in this project already makes.
  """
  def alert_subscriber_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    phone = Map.get(attrs, :phone) || unique_phone()

    {:ok, subscriber} = ZamHealthWatch.PublicAlerts.subscribe(phone)
    subscriber
  end

  defp unique_phone, do: "+2609#{System.unique_integer([:positive])}"
end
