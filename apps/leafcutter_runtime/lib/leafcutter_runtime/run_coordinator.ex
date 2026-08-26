defmodule LeafcutterRuntime.RunCoordinator do
  @moduledoc """
  Coordinates the local control-plane lifecycle for one Run.

  The coordinator retains the durable ownership token used by the Run tree. It
  remains outside the record data path and currently reacts only to fencing
  invalidation. Later lifecycle commands and coarse execution events will be
  added without routing one message per Record through this process.
  """

  use GenServer

  alias Leafcutter.Executions.{Run, Runs}

  @typedoc "Operational state retained by a local Run coordinator."
  @type state :: %{
          required(:ownership_token) => Runs.ownership_token()
        }

  @doc """
  Starts a coordinator for one local Run supervision tree.

  ## Parameters

  * `ownership_token` - The durable Run ownership token retained by the coordinator

  ## Returns

  * `{:ok, pid}` when the coordinator starts
  * `{:error, {:already_started, pid}}` when that Run coordinator already exists locally
  * `{:error, reason}` when startup fails

  ## Examples

      iex> is_pid(Process.whereis(LeafcutterRuntime.RunDynamicSupervisor))
      true

  ## Notes

  * The process is registered under `{:coordinator, run_id}` in the local Run Registry.
  * Its Registry value is the exact ownership token held by this tree generation.
  * Callers should normally start coordinators through `LeafcutterRuntime.Runs.start/1`.
  """
  @spec start_link(Runs.ownership_token()) :: GenServer.on_start()
  def start_link(ownership_token) do
    GenServer.start_link(
      __MODULE__,
      ownership_token,
      name: via_name(ownership_token)
    )
  end

  @doc """
  Stops the matching local Run tree after a fenced write reports stale ownership.

  ## Parameters

  * `ownership_token` - The token rejected by the durable write

  ## Returns

  * `:ok` after notifying the matching coordinator
  * `:ok` when the Run is not local or a newer local generation is already running

  ## Examples

      iex> LeafcutterRuntime.RunCoordinator.stale_ownership(%{
      ...>   run_id: Ecto.UUID.generate(),
      ...>   runtime_node_id: Ecto.UUID.generate(),
      ...>   generation: 1
      ...> })
      :ok

  ## Notes

  * The token must exactly match the coordinator Registry value.
  * A stale report from an older generation never terminates a newer local tree.
  * Ownership is not released because the rejected token is no longer authoritative.
  * Normal coordinator exit triggers automatic shutdown of its Run supervisor.
  """
  @spec stale_ownership(Runs.ownership_token()) :: :ok
  def stale_ownership(ownership_token) do
    case coordinator_pid(ownership_token) do
      {:ok, coordinator_pid} ->
        GenServer.cast(
          coordinator_pid,
          {:stale_ownership, ownership_token}
        )

      :error ->
        :ok
    end
  end

  @impl true
  @spec init(Runs.ownership_token()) :: {:ok, state()}
  def init(ownership_token) do
    {:ok, %{ownership_token: ownership_token}}
  end

  @impl true
  @spec handle_cast(
          {:stale_ownership, Runs.ownership_token()},
          state()
        ) :: {:noreply, state()} | {:stop, :normal, state()}
  def handle_cast(
        {:stale_ownership, ownership_token},
        %{ownership_token: ownership_token} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_cast({:stale_ownership, _ownership_token}, state) do
    {:noreply, state}
  end

  @spec coordinator_pid(Runs.ownership_token()) :: {:ok, pid()} | :error
  defp coordinator_pid(ownership_token) do
    coordinator_key = {:coordinator, ownership_token.run_id}

    case Registry.lookup(
           LeafcutterRuntime.RunRegistry,
           coordinator_key
         ) do
      [{coordinator_pid, ^ownership_token}] when is_pid(coordinator_pid) ->
        if Process.alive?(coordinator_pid) do
          {:ok, coordinator_pid}
        else
          :error
        end

      _other ->
        :error
    end
  end

  @spec via_name(Runs.ownership_token()) ::
          {:via, Registry,
           {atom(), {:coordinator, Run.id()}, Runs.ownership_token()}}
  defp via_name(ownership_token) do
    {:via, Registry,
     {
       LeafcutterRuntime.RunRegistry,
       {:coordinator, ownership_token.run_id},
       ownership_token
     }}
  end
end
