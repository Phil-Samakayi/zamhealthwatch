defmodule ZamHealthWatch.SmsReporting.Pipeline do
  @moduledoc """
  The Broadway pipeline consuming inbound SMS reports from `Producer`.

  One processor stage, no explicit batcher - report volume at this
  iteration doesn't call for batching database writes, and proving out
  Broadway's demand-driven concurrency/backpressure handling (via
  `Producer`'s `handle_demand/2`) is what this iteration exists to
  prove, not batching. Revisit if/when real volume makes batched inserts
  worth it.

  `handle_message/3` is also the one place that texts the reporter back
  (`SmsReporting.confirmation_message/1` + `SmsGateway.send_sms/2`) -
  it already has both `report_from_sms/2`'s result and the reporter's
  own `from` number, so no other module needs to be handed either one
  just to send this reply.
  """

  use Broadway

  require Logger

  alias Broadway.Message
  alias ZamHealthWatch.SmsGateway
  alias ZamHealthWatch.SmsReporting

  def start_link(opts \\ []) do
    Broadway.start_link(__MODULE__,
      name: Keyword.get(opts, :name, __MODULE__),
      producer: [
        module: {SmsReporting.Producer, []},
        concurrency: 1,
        transformer: {__MODULE__, :transform, []}
      ],
      processors: [
        default: [concurrency: 2]
      ]
    )
  end

  @doc false
  # Broadway requires every event a producer emits to already be a
  # %Broadway.Message{} - a plain GenStage producer (like Producer here)
  # emitting raw terms needs a :transformer to wrap them, which is what
  # this is. The acknowledger is SmsReporting.Acknowledger, a hand-written
  # no-op - see its moduledoc for why.
  def transform(event, _opts) do
    %Message{data: event, acknowledger: {SmsReporting.Acknowledger, :ack_ref, :ok}}
  end

  @doc """
  Pushes a raw inbound SMS message (`%{from: phone, text: body}`) into
  the pipeline named `broadway` (defaults to this module's own name,
  the one started by `ZamHealthWatch.Application`).

  `Broadway.producer_names/1` is the documented way to reach a running
  pipeline's custom producer process(es) from outside - there's no
  registered name for `Producer` itself to call `GenStage.cast/2` on
  directly, since Broadway starts and supervises producer processes
  internally.
  """
  def push(broadway \\ __MODULE__, message) do
    broadway
    |> Broadway.producer_names()
    |> Enum.random()
    |> GenStage.cast({:push, message})
  end

  @impl true
  def handle_message(_processor, %Message{data: %{from: from, text: text}} = message, _context) do
    result = SmsReporting.report_from_sms(from, text)
    SmsGateway.send_sms(from, SmsReporting.confirmation_message(result))

    case result do
      {:ok, _case} ->
        message

      {:error, reason} ->
        Logger.warning(
          "SMS report rejected (#{inspect(reason)}): from=#{from} text=#{inspect(text)}"
        )

        Message.failed(message, reason)
    end
  end
end
