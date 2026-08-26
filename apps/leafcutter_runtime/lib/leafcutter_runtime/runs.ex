defmodule LeafcutterRuntime.Runs do
  @moduledoc """
  Public workflow module for local per-Run supervision.

  Startup first acquires durable ownership from `Leafcutter.Executions.Runs`
  and only then starts the local OTP tree. PostgreSQL decides who owns a Run;
  the local Registry and supervisors represent that ownership inside one BEAM
  node.
  """

  alias Leafcutter.Executions.Run
  alias Leafcutter.Executions.Runs, as: DurableRuns

  alias LeafcutterRuntime.{
    NodeHeartbeat,
    RunCoordinator,
    RunDynamicSupervisor,
    RunSupervisor
  }

  @max_local_start_attempts 3

  @typedoc "A local Run supervisor and the durable token retained by its tree."
  @type local_run :: %{
          required(:run_supervisor_pid) => pid(),
          required(:ownership_token) => DurableRuns.ownership_token()
        }

  @typedoc "Error returned when a local Run tree cannot be started."
  @type start_error ::
          DurableRuns.claim_error()
          | {:run_supervisor_start_failed, term()}
          | {:run_supervisor_start_failed, term(), DurableRuns.release_error()}

  @doc """
  Claims a Run for the current runtime incarnation and starts its local tree.

  ## Parameters

  * `run_id` - The identifier of the durable Run to supervise locally

  ## Returns

  * `{:ok, run_supervisor_pid}` when a new local Run tree starts
  * `{:ok, run_supervisor_pid}` when the same current generation is already local
  * `{:error, claim_error}` when durable ownership cannot be acquired
  * `{:error, {:run_supervisor_start_failed, reason}}` when local startup fails and ownership is released
  * `{:error, {:run_supervisor_start_failed, reason, release_error}}` when startup and ownership cleanup both fail

  ## Examples

      iex> LeafcutterRuntime.Runs.start(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :run_not_found}

  ## Notes

  * Durable claim always happens before local process startup.
  * Repeating startup for the same local generation is idempotent.
  * A locally registered older generation is terminated before the current token starts.
  * A failed durable claim removes any local tree that can no longer prove ownership.
  * Failed startup releases the claimed token unless another matching local tree won the race.
  * This workflow does not create Runs or perform automatic recovery scanning.
  """
  @spec start(Run.id()) :: {:ok, pid()} | {:error, start_error()}
  def start(run_id) do
    runtime_node_id = NodeHeartbeat.runtime_node_id()

    case DurableRuns.claim(run_id, runtime_node_id) do
      {:ok, ownership_token} ->
        ensure_local_tree(ownership_token)

      {:error, reason} ->
        terminate_registered_tree(run_id)
        {:error, reason}
    end
  end

  @doc """
  Returns the local supervision tree registered for a Run.

  ## Parameters

  * `run_id` - The identifier used as the local Run Registry key

  ## Returns

  * `{:ok, local_run}` when a live Run supervisor is registered locally
  * `:error` when the Run has no live local supervision tree

  ## Examples

      iex> LeafcutterRuntime.Runs.lookup(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      :error

  ## Notes

  * Lookup is local and does not query durable ownership.
  * The Registry value is the exact ownership token retained by the tree.
  * PostgreSQL remains authoritative even when a local process is present.
  """
  @spec lookup(Run.id()) :: {:ok, local_run()} | :error
  def lookup(run_id) do
    case Registry.lookup(LeafcutterRuntime.RunRegistry, run_id) do
      [
        {run_supervisor_pid,
         %{
           run_id: ^run_id,
           runtime_node_id: runtime_node_id,
           generation: generation
         } = ownership_token}
      ]
      when is_pid(run_supervisor_pid) and is_binary(runtime_node_id) and
             is_integer(generation) and generation > 0 ->
        if Process.alive?(run_supervisor_pid) do
          {:ok,
           %{
             run_supervisor_pid: run_supervisor_pid,
             ownership_token: ownership_token
           }}
        else
          :error
        end

      _other ->
        :error
    end
  end

  @doc """
  Stops a local Run tree and releases its durable ownership.

  ## Parameters

  * `run_id` - The identifier of the locally supervised Run

  ## Returns

  * `:ok` when ownership is released and the local tree is terminated
  * `:ok` when no local tree exists
  * `{:error, :run_not_found}` when the durable Run disappeared before release
  * `{:error, :stale_ownership}` when the local token has already been superseded

  ## Examples

      iex> LeafcutterRuntime.Runs.stop(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      :ok

  ## Notes

  * Durable release is attempted before local termination.
  * The local tree is terminated even when release reports stale ownership.
  * Release preserves Run status and generation.
  * A later start must perform a fresh durable claim.
  """
  @spec stop(Run.id()) :: :ok | {:error, DurableRuns.release_error()}
  def stop(run_id) do
    case lookup(run_id) do
      {:ok,
       %{
         run_supervisor_pid: run_supervisor_pid,
         ownership_token: ownership_token
       }} ->
        release_result = DurableRuns.release(ownership_token)
        terminate_local_tree(run_supervisor_pid)
        release_result

      :error ->
        :ok
    end
  end

  @doc """
  Removes the matching local tree after a critical write rejects its fencing token.

  ## Parameters

  * `ownership_token` - The token rejected as stale by the durable write

  ## Returns

  * `:ok` after notifying the matching local coordinator
  * `:ok` when no matching local generation exists

  ## Examples

      iex> LeafcutterRuntime.Runs.stale_ownership(%{
      ...>   run_id: Ecto.UUID.generate(),
      ...>   runtime_node_id: Ecto.UUID.generate(),
      ...>   generation: 1
      ...> })
      :ok

  ## Notes

  * The full token is compared, not only the Run identifier.
  * A late stale report from an old generation cannot terminate a newer tree.
  * Stale ownership is not released because another owner may already be current.
  * Normal coordinator exit shuts down the complete per-Run supervisor.
  """
  @spec stale_ownership(DurableRuns.ownership_token()) :: :ok
  def stale_ownership(ownership_token) do
    case lookup(ownership_token.run_id) do
      {:ok, %{ownership_token: ^ownership_token}} ->
        RunCoordinator.stale_ownership(ownership_token)

      _not_matching ->
        :ok
    end
  end

  @spec ensure_local_tree(DurableRuns.ownership_token()) ::
          {:ok, pid()} | {:error, start_error()}
  defp ensure_local_tree(ownership_token) do
    ensure_local_tree(ownership_token, @max_local_start_attempts)
  end

  @spec ensure_local_tree(
          DurableRuns.ownership_token(),
          non_neg_integer()
        ) :: {:ok, pid()} | {:error, start_error()}
  defp ensure_local_tree(ownership_token, 0) do
    release_failed_start(
      ownership_token,
      :local_registration_conflict
    )
  end

  defp ensure_local_tree(ownership_token, attempts_remaining) do
    case lookup(ownership_token.run_id) do
      {:ok,
       %{
         run_supervisor_pid: run_supervisor_pid,
         ownership_token: ^ownership_token
       }} ->
        {:ok, run_supervisor_pid}

      {:ok, %{run_supervisor_pid: stale_supervisor_pid}} ->
        terminate_local_tree(stale_supervisor_pid)
        ensure_local_tree(ownership_token, attempts_remaining - 1)

      :error ->
        start_local_tree(ownership_token, attempts_remaining)
    end
  end

  @spec start_local_tree(
          DurableRuns.ownership_token(),
          pos_integer()
        ) :: {:ok, pid()} | {:error, start_error()}
  defp start_local_tree(ownership_token, attempts_remaining) do
    child_spec = {RunSupervisor, ownership_token}

    case DynamicSupervisor.start_child(
           RunDynamicSupervisor,
           child_spec
         ) do
      {:ok, run_supervisor_pid} ->
        {:ok, run_supervisor_pid}

      {:error, {:already_started, _run_supervisor_pid}} ->
        ensure_local_tree(ownership_token, attempts_remaining - 1)

      {:error, reason} ->
        reconcile_start_failure(ownership_token, reason)
    end
  end

  @spec reconcile_start_failure(
          DurableRuns.ownership_token(),
          term()
        ) :: {:ok, pid()} | {:error, start_error()}
  defp reconcile_start_failure(ownership_token, reason) do
    case lookup(ownership_token.run_id) do
      {:ok,
       %{
         run_supervisor_pid: run_supervisor_pid,
         ownership_token: ^ownership_token
       }} ->
        {:ok, run_supervisor_pid}

      _not_started ->
        release_failed_start(ownership_token, reason)
    end
  end

  @spec release_failed_start(
          DurableRuns.ownership_token(),
          term()
        ) :: {:ok, pid()} | {:error, start_error()}
  defp release_failed_start(ownership_token, reason) do
    case lookup(ownership_token.run_id) do
      {:ok,
       %{
         run_supervisor_pid: run_supervisor_pid,
         ownership_token: ^ownership_token
       }} ->
        {:ok, run_supervisor_pid}

      _not_started ->
        case DurableRuns.release(ownership_token) do
          :ok ->
            {:error, {:run_supervisor_start_failed, reason}}

          {:error, release_error} ->
            {:error,
             {
               :run_supervisor_start_failed,
               reason,
               release_error
             }}
        end
    end
  end

  @spec terminate_registered_tree(Run.id()) :: :ok
  defp terminate_registered_tree(run_id) do
    case lookup(run_id) do
      {:ok, %{run_supervisor_pid: run_supervisor_pid}} ->
        terminate_local_tree(run_supervisor_pid)

      :error ->
        :ok
    end
  end

  @spec terminate_local_tree(pid()) :: :ok
  defp terminate_local_tree(run_supervisor_pid) do
    case DynamicSupervisor.terminate_child(
           RunDynamicSupervisor,
           run_supervisor_pid
         ) do
      :ok ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end
end
