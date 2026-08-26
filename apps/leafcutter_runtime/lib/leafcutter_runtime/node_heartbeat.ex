defmodule LeafcutterRuntime.NodeHeartbeat do
  @moduledoc """
  Persists and emits heartbeats for one local BEAM runtime incarnation.

  The application generates one runtime node identifier at startup. A restart
  of this process preserves that identifier, while a new application start
  creates a new incarnation.
  """

  use GenServer

  require Logger

  alias Leafcutter.Executions.{Nodes, RuntimeNode}

  @heartbeat_event [:leafcutter, :runtime, :node, :heartbeat]
  @default_interval 15_000
  @default_mode :durable

  @typedoc "The heartbeat behavior used by a process instance."
  @type mode :: :durable | :telemetry_only

  @typedoc "Startup options for the node heartbeat process."
  @type start_options :: %{
          required(:runtime_node_id) => RuntimeNode.id(),
          optional(:interval) => pos_integer(),
          optional(:mode) => mode(),
          optional(:name) => atom() | nil,
          optional(:node_name) => String.t()
        }

  @typedoc "Operational state held by the node heartbeat process."
  @type state :: %{
          interval: pos_integer(),
          mode: mode(),
          node_name: String.t(),
          runtime_node_id: RuntimeNode.id()
        }

  @doc """
  Starts the node heartbeat process.

  ## Parameters

  * `opts` - The runtime incarnation identifier and optional process configuration

  ## Returns

  * `{:ok, pid}` when the heartbeat process starts successfully
  * `{:error, reason}` when the process cannot be started

  ## Examples

      iex> Process.whereis(LeafcutterRuntime.NodeHeartbeat) |> is_pid()
      true

  ## Notes

  * The process records one heartbeat when it starts and then periodically.
  * Durable mode persists liveness before emitting Telemetry.
  * Telemetry-only mode exists for isolated tests using the SQL Sandbox.
  * A database failure is logged and retried on the next interval without crashing the process.
  * Heartbeats record liveness but do not grant or renew Run ownership.
  """
  @spec start_link(start_options()) :: GenServer.on_start()
  def start_link(opts) do
    opts
    |> Map.get(:name, __MODULE__)
    |> genserver_options()
    |> then(&GenServer.start_link(__MODULE__, opts, &1))
  end

  @doc """
  Returns the identifier of the current runtime incarnation.

  ## Returns

  * The UUID generated when the runtime application started

  ## Examples

      iex> match?(
      ...>   {:ok, _runtime_node_id},
      ...>   LeafcutterRuntime.NodeHeartbeat.runtime_node_id()
      ...>   |> Ecto.UUID.cast()
      ...> )
      true

  ## Notes

  * Restarting only the heartbeat process preserves this identifier.
  * Restarting the runtime application creates a new identifier.
  * The Erlang node name is metadata and is not the runtime incarnation identity.
  """
  @spec runtime_node_id() :: RuntimeNode.id()
  def runtime_node_id do
    GenServer.call(__MODULE__, :runtime_node_id)
  end

  @impl true
  @spec init(start_options()) :: {:ok, state()}
  def init(opts) do
    state = %{
      runtime_node_id:
        opts
        |> Map.fetch!(:runtime_node_id)
        |> validate_runtime_node_id!(),
      node_name:
        opts
        |> Map.get(:node_name, Atom.to_string(node()))
        |> validate_node_name!(),
      interval:
        opts
        |> Map.get(:interval, configured_interval())
        |> validate_interval!(),
      mode:
        opts
        |> Map.get(:mode, configured_mode())
        |> validate_mode!()
    }

    send(self(), :heartbeat)

    {:ok, state}
  end

  @impl true
  @spec handle_call(:runtime_node_id, GenServer.from(), state()) ::
          {:reply, RuntimeNode.id(), state()}
  def handle_call(:runtime_node_id, _from, state) do
    {:reply, state.runtime_node_id, state}
  end

  @impl true
  @spec handle_info(:heartbeat, state()) :: {:noreply, state()}
  def handle_info(:heartbeat, state) do
    record_heartbeat(state)
    schedule_heartbeat(state.interval)

    {:noreply, state}
  end

  @spec configured_interval() :: term()
  defp configured_interval do
    :leafcutter_runtime
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:interval, @default_interval)
  end

  @spec configured_mode() :: term()
  defp configured_mode do
    :leafcutter_runtime
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:mode, @default_mode)
  end

  @spec validate_runtime_node_id!(term()) :: RuntimeNode.id()
  defp validate_runtime_node_id!(runtime_node_id) do
    case Ecto.UUID.cast(runtime_node_id) do
      {:ok, runtime_node_id} ->
        runtime_node_id

      :error ->
        raise ArgumentError,
              "expected runtime node identifier to be a valid UUID, got: #{inspect(runtime_node_id)}"
    end
  end

  @spec validate_node_name!(term()) :: String.t()
  defp validate_node_name!(node_name)
       when is_binary(node_name) and byte_size(node_name) > 0 and byte_size(node_name) <= 255 do
    node_name
  end

  defp validate_node_name!(node_name) do
    raise ArgumentError,
          "expected node name to be a non-empty string containing at most 255 bytes, got: #{inspect(node_name)}"
  end

  @spec validate_interval!(term()) :: pos_integer()
  defp validate_interval!(interval) when is_integer(interval) and interval > 0, do: interval

  defp validate_interval!(interval) do
    raise ArgumentError,
          "expected node heartbeat interval to be a positive integer, got: #{inspect(interval)}"
  end

  @spec validate_mode!(term()) :: mode()
  defp validate_mode!(mode) when mode in [:durable, :telemetry_only], do: mode

  defp validate_mode!(mode) do
    raise ArgumentError,
          "expected node heartbeat mode to be :durable or :telemetry_only, got: #{inspect(mode)}"
  end

  @spec genserver_options(atom() | nil) :: [] | [{:name, atom()}]
  defp genserver_options(nil), do: []
  defp genserver_options(name), do: [name: name]

  @spec schedule_heartbeat(pos_integer()) :: reference()
  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end

  @spec record_heartbeat(state()) :: :ok
  defp record_heartbeat(%{mode: :telemetry_only} = state) do
    emit_heartbeat(state)
  end

  defp record_heartbeat(%{mode: :durable} = state) do
    case Nodes.heartbeat(state.runtime_node_id, state.node_name) do
      {:ok, _runtime_node} ->
        emit_heartbeat(state)

      {:error, changeset} ->
        log_persistence_failure(state, inspect(changeset.errors))
    end
  rescue
    exception ->
      log_persistence_failure(state, Exception.message(exception))
  catch
    :exit, reason ->
      log_persistence_failure(state, inspect(reason))
  end

  @spec emit_heartbeat(state()) :: :ok
  defp emit_heartbeat(state) do
    :telemetry.execute(
      @heartbeat_event,
      %{system_time: System.system_time(:millisecond)},
      %{
        node: node(),
        runtime_node_id: state.runtime_node_id
      }
    )
  end

  @spec log_persistence_failure(state(), String.t()) :: :ok
  defp log_persistence_failure(state, reason) do
    Logger.warning(
      "Unable to persist runtime node heartbeat for #{state.runtime_node_id} " <>
        "(#{state.node_name}): #{reason}"
    )
  end
end
