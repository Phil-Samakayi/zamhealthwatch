defmodule ZamHealthWatch.SmsReporting.Producer do
  @moduledoc """
  A minimal push-based `GenStage` producer for `SmsReporting.Pipeline`.

  Broadway's off-the-shelf producers (SQS, RabbitMQ, Kafka) all *pull*
  from an external queue - none fit "a webhook controller pushes
  messages in as HTTP requests arrive", which is what an inbound
  SMS/USSD webhook actually looks like. This is the standard, documented
  Broadway pattern for that shape: a small custom `GenStage` producer
  holding its own buffer and outstanding demand, fed by `push/2` from
  outside rather than polling anything.

  Deliberately minimal - no persistence, no back-pressure signalling
  beyond what `GenStage` gives for free by only dispatching up to
  outstanding demand. Proving the Broadway wiring itself is this
  iteration's goal, not building a production-grade queue. Revisit (e.g.
  a Postgres-backed queue, matching the pattern `PublicAlerts` already
  uses via Oban) if messages need to survive an app restart - right now
  an inbound SMS that arrives during a deploy is simply lost, same as it
  would be for any in-memory-only pipeline.
  """

  use GenStage

  @impl true
  def init(_arg) do
    {:producer, {:queue.new(), 0}}
  end

  @impl true
  def handle_demand(incoming_demand, {queue, demand}) do
    dispatch(queue, demand + incoming_demand)
  end

  @impl true
  def handle_cast({:push, message}, {queue, demand}) do
    dispatch(:queue.in(message, queue), demand)
  end

  defp dispatch(queue, demand) do
    {items, queue, demand} = take(queue, demand, [])
    {:noreply, items, {queue, demand}}
  end

  defp take(queue, 0, acc), do: {Enum.reverse(acc), queue, 0}

  defp take(queue, demand, acc) do
    case :queue.out(queue) do
      {{:value, item}, queue} -> take(queue, demand - 1, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue, demand}
    end
  end
end
