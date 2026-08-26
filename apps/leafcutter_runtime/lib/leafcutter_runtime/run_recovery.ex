defmodule LeafcutterRuntime.RunRecovery do
  @moduledoc """
  Reconciles durable Run ownership with local per-Run supervision.

  PostgreSQL remains authoritative. This process periodically reconstructs
  local trees already owned by the current runtime incarnation and atomically
  claims recoverable running Runs in bounded batches.
  """

  use GenServer

  require Logger

  alias Leafcutter.Executions.{Run, RuntimeNode}
  alias Leafcutter.Executions.Runs, as: DurableRuns
  alias LeafcutterRuntime.Runs, as: RuntimeRuns

  @default_enabled true
  @default_initial_delay 1_000
  @default_scan_interval 5_000
  @default_batch_size 25
  @default_drain_delay 100
  @default_initial_backoff 1_000
  @default_max_backoff 30_000
  @shutdown_timeout 30_000

  @typedoc "Operational retry state for one Run whose local startup failed."
  @type retry_state :: %{
          required(:attempt) => pos_integer(),
          required(:retry_at) => integer()
        }

  @typedoc "Startup options for the automatic Run recovery process."
  @type start_options :: %{
          required(:runtime_node_id) => RuntimeNode.id(),
          optional(:enabled) => boolean(),
          optional(:name) => atom() | nil,
          optional(:initial_delay) => non_neg_integer(),
          optional(:scan_interval) => pos_integer(),
          optional(:batch_size) => pos_integer(),
          optional(:drain_delay) => non_neg_integer(),
          optional(:initial_backoff) => pos_integer(),
          optional(:max_backoff) => pos_integer()
        }

  @typedoc "Operational state retained by the recovery process."
  @type state :: %{
          required(:runtime_node_id) => RuntimeNode.id(),
          required(:initial_delay) => non_neg_integer(),
          required(:scan_interval) => pos_integer(),
          required(:batch_size) => pos_integer(),
          required(:drain_delay) => non_neg_integer(),
          required(:initial_backoff) => pos_integer(),
          required(:max_backoff) => pos_integer(),
          required(:current_backoff) => pos_integer(),
          required(:retry_failures) => %{optional(Run.id()) => retry_state()}
        }

  @doc """
  Returns the supervised child specification for one recovery process.

  ## Parameters

  * `opts` - The runtime incarnation identifier and optional recovery configuration

  ## Returns

  * A permanent worker specification with a 30-second graceful shutdown window

  ## Examples

      iex> runtime_node_id = Ecto.UUID.generate()

      iex> %{type: :worker, restart: :permanent, shutdown: 30_000} =
      ...>   LeafcutterRuntime.RunRecovery.child_spec(%{
      ...>     runtime_node_id: runtime_node_id
      ...>   })

  ## Notes

  * The runtime incarnation identifier is part of the child identifier.
  * Graceful shutdown attempts to release locally owned Runs before the process exits.
  * Abnormal crashes do not release ownership or terminate local Run trees.
  """
  @spec child_spec(start_options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Map.fetch!(opts, :runtime_node_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: @shutdown_timeout,
      type: :worker
    }
  end

  @doc """
  Starts the automatic Run recovery process.

  ## Parameters

  * `opts` - The runtime incarnation identifier and optional recovery configuration

  ## Returns

  * `{:ok, pid}` when recovery is enabled and the process starts
  * `:ignore` when recovery is disabled
  * `{:error, reason}` when the process cannot be started

  ## Examples

      iex> is_map(
      ...>   LeafcutterRuntime.RunRecovery.child_spec(%{
      ...>     runtime_node_id: Ecto.UUID.generate(),
      ...>     enabled: false
      ...>   })
      ...> )
      true

  ## Notes

  * Production recovery is enabled through application configuration.
  * Tests may start isolated unnamed processes with explicit options.
  * The process performs no durable work when disabled.
  """
  @spec start_link(start_options()) :: GenServer.on_start()
  def start_link(opts) do
    enabled =
      opts
      |> option(:enabled, @default_enabled)
      |> validate_boolean!(:enabled)

    if enabled do
      opts
      |> Map.get(:name, __MODULE__)
      |> genserver_options()
      |> then(&GenServer.start_link(__MODULE__, opts, &1))
    else
      :ignore
    end
  end

  @impl true
  @spec init(start_options()) :: {:ok, state()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    initial_backoff =
      opts
      |> option(:initial_backoff, @default_initial_backoff)
      |> validate_positive_integer!(:initial_backoff)

    max_backoff =
      opts
      |> option(:max_backoff, @default_max_backoff)
      |> validate_positive_integer!(:max_backoff)

    validate_backoff_bounds!(initial_backoff, max_backoff)

    state = %{
      runtime_node_id:
        opts
        |> Map.fetch!(:runtime_node_id)
        |> validate_runtime_node_id!(),
      initial_delay:
        opts
        |> option(:initial_delay, @default_initial_delay)
        |> validate_non_negative_integer!(:initial_delay),
      scan_interval:
        opts
        |> option(:scan_interval, @default_scan_interval)
        |> validate_positive_integer!(:scan_interval),
      batch_size:
        opts
        |> option(:batch_size, @default_batch_size)
        |> validate_positive_integer!(:batch_size),
      drain_delay:
        opts
        |> option(:drain_delay, @default_drain_delay)
        |> validate_non_negative_integer!(:drain_delay),
      initial_backoff: initial_backoff,
      max_backoff: max_backoff,
      current_backoff: initial_backoff,
      retry_failures: %{}
    }

    schedule_scan(state.initial_delay)

    {:ok, state}
  end

  @impl true
  @spec handle_info(:scan, state()) :: {:noreply, state()}
  def handle_info(:scan, state) do
    case recover(state) do
      {:ok, next_state, claimed_count} ->
        delay = next_scan_delay(next_state, claimed_count)
        schedule_scan(delay)

        {:noreply,
         %{
           next_state
           | current_backoff: next_state.initial_backoff
         }}

      {:error, reason, next_state} ->
        Logger.warning(
          "Unable to reconcile recoverable Runs for runtime node " <>
            "#{next_state.runtime_node_id}: #{inspect(reason)}"
        )

        schedule_scan(next_state.current_backoff)

        {:noreply,
         %{
           next_state
           | current_backoff: next_global_backoff(next_state)
         }}
    end
  end

  @impl true
  @spec terminate(term(), state()) :: :ok
  def terminate(reason, _state) do
    if graceful_shutdown?(reason) do
      stop_local_runs()
    end

    :ok
  end

  @spec recover(state()) ::
          {:ok, state(), non_neg_integer()}
          | {:error, term(), state()}
  defp recover(state) do
    perform_recovery(state)
  rescue
    exception ->
      {:error, {:exception, Exception.message(exception)}, state}
  catch
    :exit, reason ->
      {:error, {:exit, reason}, state}

    kind, reason ->
      {:error, {kind, reason}, state}
  end

  @spec perform_recovery(state()) ::
          {:ok, state(), non_neg_integer()}
          | {:error, DurableRuns.recovery_claim_error(), state()}
  defp perform_recovery(state) do
    owned_tokens =
      DurableRuns.list_owned_tokens(state.runtime_node_id)

    next_state =
      owned_tokens
      |> reconcile_local_trees(state)
      |> start_owned_tokens(owned_tokens)

    excluded_run_ids = active_retry_run_ids(next_state)

    case DurableRuns.claim_recoverable(
           next_state.runtime_node_id,
           next_state.batch_size,
           excluded_run_ids
         ) do
      {:ok, ownership_tokens} ->
        recovered_state =
          Enum.reduce(
            ownership_tokens,
            next_state,
            &start_recovered_token/2
          )

        {:ok, recovered_state, length(ownership_tokens)}

      {:error, reason} ->
        {:error, reason, next_state}
    end
  end

  @spec reconcile_local_trees(
          [DurableRuns.ownership_token()],
          state()
        ) :: state()
  defp reconcile_local_trees(owned_tokens, state) do
    durable_tokens_by_run =
      Map.new(owned_tokens, fn ownership_token ->
        {ownership_token.run_id, ownership_token}
      end)

    Enum.reduce(RuntimeRuns.list_local(), state, fn
      %{ownership_token: local_token}, current_state ->
        case Map.get(durable_tokens_by_run, local_token.run_id) do
          ^local_token ->
            clear_retry_failure(current_state, local_token.run_id)

          _different_or_missing_token ->
            RuntimeRuns.stale_ownership(local_token)
            clear_retry_failure(current_state, local_token.run_id)
        end
    end)
  end

  @spec start_owned_tokens(
          state(),
          [DurableRuns.ownership_token()]
        ) :: state()
  defp start_owned_tokens(state, owned_tokens) do
    Enum.reduce(owned_tokens, state, &start_recovered_token/2)
  end

  @spec start_recovered_token(
          DurableRuns.ownership_token(),
          state()
        ) :: state()
  defp start_recovered_token(ownership_token, state) do
    if retry_delayed?(state, ownership_token.run_id) do
      state
    else
      case RuntimeRuns.start_claimed(ownership_token) do
        {:ok, _run_supervisor_pid} ->
          clear_retry_failure(state, ownership_token.run_id)

        {:error, reason} ->
          Logger.warning(
            "Unable to start recovered Run #{ownership_token.run_id}: " <>
              inspect(reason)
          )

          record_retry_failure(state, ownership_token.run_id)
      end
    end
  end

  @spec retry_delayed?(state(), Run.id()) :: boolean()
  defp retry_delayed?(state, run_id) do
    case Map.get(state.retry_failures, run_id) do
      %{retry_at: retry_at} ->
        retry_at > System.monotonic_time(:millisecond)

      nil ->
        false
    end
  end

  @spec active_retry_run_ids(state()) :: [Run.id()]
  defp active_retry_run_ids(state) do
    monotonic_now = System.monotonic_time(:millisecond)

    state.retry_failures
    |> Enum.flat_map(fn
      {run_id, %{retry_at: retry_at}} when retry_at > monotonic_now ->
        [run_id]

      {_run_id, _retry_state} ->
        []
    end)
    |> Enum.sort()
  end

  @spec record_retry_failure(state(), Run.id()) :: state()
  defp record_retry_failure(state, run_id) do
    previous_attempt =
      state.retry_failures
      |> Map.get(run_id, %{attempt: 0, retry_at: 0})
      |> Map.fetch!(:attempt)

    attempt = previous_attempt + 1

    retry_at =
      System.monotonic_time(:millisecond) +
        retry_delay(
          state.initial_backoff,
          state.max_backoff,
          attempt
        )

    retry_failure = %{
      attempt: attempt,
      retry_at: retry_at
    }

    %{
      state
      | retry_failures:
          Map.put(
            state.retry_failures,
            run_id,
            retry_failure
          )
    }
  end

  @spec clear_retry_failure(state(), Run.id()) :: state()
  defp clear_retry_failure(state, run_id) do
    %{
      state
      | retry_failures: Map.delete(state.retry_failures, run_id)
    }
  end

  @spec retry_delay(pos_integer(), pos_integer(), pos_integer()) :: pos_integer()
  defp retry_delay(initial_backoff, max_backoff, attempt) do
    grow_retry_delay(
      initial_backoff,
      max_backoff,
      attempt - 1
    )
  end

  @spec grow_retry_delay(pos_integer(), pos_integer(), non_neg_integer()) ::
          pos_integer()
  defp grow_retry_delay(delay, _max_backoff, 0), do: delay
  defp grow_retry_delay(delay, max_backoff, _remaining) when delay >= max_backoff,
    do: max_backoff

  defp grow_retry_delay(delay, max_backoff, remaining) do
    grow_retry_delay(
      min(delay * 2, max_backoff),
      max_backoff,
      remaining - 1
    )
  end

  @spec next_scan_delay(state(), non_neg_integer()) :: non_neg_integer()
  defp next_scan_delay(state, claimed_count) do
    base_delay =
      if claimed_count == state.batch_size do
        state.drain_delay
      else
        state.scan_interval
      end

    case next_retry_delay(state.retry_failures) do
      nil -> base_delay
      retry_delay -> min(base_delay, retry_delay)
    end
  end

  @spec next_retry_delay(%{optional(Run.id()) => retry_state()}) ::
          non_neg_integer() | nil
  defp next_retry_delay(retry_failures) do
    monotonic_now = System.monotonic_time(:millisecond)

    retry_failures
    |> Enum.flat_map(fn
      {_run_id, %{retry_at: retry_at}} when retry_at > monotonic_now ->
        [retry_at - monotonic_now]

      {_run_id, _retry_state} ->
        []
    end)
    |> case do
      [] -> nil
      delays -> Enum.min(delays)
    end
  end

  @spec next_global_backoff(state()) :: pos_integer()
  defp next_global_backoff(state) do
    min(state.current_backoff * 2, state.max_backoff)
  end

  @spec graceful_shutdown?(term()) :: boolean()
  defp graceful_shutdown?(:normal), do: true
  defp graceful_shutdown?(:shutdown), do: true
  defp graceful_shutdown?({:shutdown, _reason}), do: true
  defp graceful_shutdown?(_reason), do: false

  @spec stop_local_runs() :: :ok
  defp stop_local_runs do
    Enum.each(RuntimeRuns.list_local(), fn local_run ->
      run_id = local_run.ownership_token.run_id

      case RuntimeRuns.stop(run_id) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Unable to release Run #{run_id} during runtime shutdown: " <>
              inspect(reason)
          )
      end
    end)

    :ok
  end

  @spec schedule_scan(non_neg_integer()) :: reference()
  defp schedule_scan(delay) do
    Process.send_after(self(), :scan, delay)
  end

  @spec option(start_options(), atom(), term()) :: term()
  defp option(opts, key, default) do
    case Map.fetch(opts, key) do
      {:ok, value} -> value
      :error -> configured_value(key, default)
    end
  end

  @spec configured_value(atom(), term()) :: term()
  defp configured_value(key, default) do
    :leafcutter_runtime
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  @spec validate_runtime_node_id!(term()) :: RuntimeNode.id()
  defp validate_runtime_node_id!(runtime_node_id) do
    case Ecto.UUID.cast(runtime_node_id) do
      {:ok, runtime_node_id} ->
        runtime_node_id

      :error ->
        raise ArgumentError,
              "expected runtime node identifier to be a valid UUID, got: " <>
                inspect(runtime_node_id)
    end
  end

  @spec validate_boolean!(term(), atom()) :: boolean()
  defp validate_boolean!(value, _name) when is_boolean(value), do: value

  defp validate_boolean!(value, name) do
    raise ArgumentError,
          "expected #{name} to be a boolean, got: #{inspect(value)}"
  end

  @spec validate_positive_integer!(term(), atom()) :: pos_integer()
  defp validate_positive_integer!(value, _name)
       when is_integer(value) and value > 0,
       do: value

  defp validate_positive_integer!(value, name) do
    raise ArgumentError,
          "expected #{name} to be a positive integer, got: #{inspect(value)}"
  end

  @spec validate_non_negative_integer!(term(), atom()) :: non_neg_integer()
  defp validate_non_negative_integer!(value, _name)
       when is_integer(value) and value >= 0,
       do: value

  defp validate_non_negative_integer!(value, name) do
    raise ArgumentError,
          "expected #{name} to be a non-negative integer, got: " <>
            inspect(value)
  end

  @spec validate_backoff_bounds!(pos_integer(), pos_integer()) :: :ok
  defp validate_backoff_bounds!(initial_backoff, max_backoff)
       when initial_backoff <= max_backoff,
       do: :ok

  defp validate_backoff_bounds!(initial_backoff, max_backoff) do
    raise ArgumentError,
          "expected max_backoff to be greater than or equal to " <>
            "initial_backoff, got: #{inspect(max_backoff)} < " <>
            inspect(initial_backoff)
  end

  @spec genserver_options(atom() | nil) :: [] | [{:name, atom()}]
  defp genserver_options(nil), do: []
  defp genserver_options(name), do: [name: name]
end
