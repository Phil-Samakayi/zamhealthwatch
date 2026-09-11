defmodule ZamHealthWatchWeb.TimeHelpers do
  @moduledoc """
  Shared "time ago" formatting - pulled out now that a third LiveView
  (`DrugLive.Index`) needs the exact same private function `LabLive.Index`
  and `VaccinationLive.Index` each carried their own copy of. Same
  "revisit once a third consumer needs it" trigger this project already
  applied to `Case.disease_options/0`/`disease_label/1` in Iteration 5 -
  two copies wasn't yet a pattern worth generalizing, three is.
  """

  @doc """
  Returns a short relative-time string for a past `DateTime` (e.g.
  "3m ago", "2h ago", "1d ago"), or "just now" for anything under a
  minute old.

  ## Examples

      iex> time_ago(DateTime.utc_now())
      "just now"

  """
  def time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end
end
