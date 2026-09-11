defmodule ZamHealthWatch.SmsReporting.Acknowledger do
  @moduledoc """
  A no-op `Broadway.Acknowledger` for `Producer`'s messages.

  `Producer` has no external durable queue to ack a message back to - an
  inbound SMS lives only in its in-memory buffer for as long as it takes
  to dispatch (see `Producer`'s own moduledoc on that trade-off) - so
  there's genuinely nothing for `ack/3` to do. Written by hand rather
  than reaching for a built-in Broadway no-op acknowledger, since this
  session can't check Broadway's exact current module names against
  live docs; `Broadway.Acknowledger`'s `ack/3` callback contract is
  the stable, documented part being relied on here.
  """

  @behaviour Broadway.Acknowledger

  @impl true
  def ack(_ack_ref, _successful, _failed), do: :ok
end
