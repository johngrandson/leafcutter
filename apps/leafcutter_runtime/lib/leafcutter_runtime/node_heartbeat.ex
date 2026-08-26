defmodule LeafcutterRuntime.NodeHeartbeat do
  @moduledoc """
  Emits an ephemeral heartbeat for the local BEAM node.

  This initial heartbeat is intentionally Telemetry-only. Durable node liveness,
  Run ownership, and fencing remain PostgreSQL concerns and will be materialized
  together with the Executions persistence model.
  """

  use GenServer

  @heartbeat_event [:leafcutter, :runtime, :node, :heartbeat]
  @default_interval 15_000

  @type state :: %{
          interval: pos_integer()
        }

  @doc """
  Starts the node heartbeat process.

  ## Parameters

  * `opts` - Optional startup configuration

  ## Returns

  * `{:ok, pid}` when the heartbeat process starts successfully
  * `{:error, reason}` when the process cannot be started

  ## Examples

      iex> Process.whereis(LeafcutterRuntime.NodeHeartbeat) |> is_pid()
      true

  ## Notes

  * The process emits one heartbeat when it starts and then periodically.
  * Heartbeats are ephemeral and are not an ownership authority.
  * The interval defaults to application configuration and must be positive.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = opts |> Keyword.get(:interval, configured_interval()) |> validate_interval!()

    emit_heartbeat()
    schedule_heartbeat(interval)

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:heartbeat, %{interval: interval} = state) do
    emit_heartbeat()
    schedule_heartbeat(interval)

    {:noreply, state}
  end

  @spec configured_interval() :: pos_integer()
  defp configured_interval do
    :leafcutter_runtime
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:interval, @default_interval)
  end

  @spec validate_interval!(term()) :: pos_integer()
  defp validate_interval!(interval) when is_integer(interval) and interval > 0, do: interval

  defp validate_interval!(interval) do
    raise ArgumentError,
          "expected node heartbeat interval to be a positive integer, got: #{inspect(interval)}"
  end

  @spec schedule_heartbeat(pos_integer()) :: reference()
  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end

  @spec emit_heartbeat() :: :ok
  defp emit_heartbeat do
    :telemetry.execute(
      @heartbeat_event,
      %{system_time: System.system_time(:millisecond)},
      %{node: node()}
    )
  end
end
