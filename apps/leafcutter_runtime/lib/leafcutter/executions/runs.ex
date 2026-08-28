defmodule Leafcutter.Executions.Runs do
  @moduledoc """
  Public capability module for durable Run ownership and fencing.

  PostgreSQL serializes ownership changes for each Run. Every new owner receives
  a greater `generation`, which must be included in future critical writes so a
  stale runtime process cannot mutate a Run after recovery by another node.
  """

  import Ecto.Query

  alias Ecto.{Changeset, Multi}
  alias Leafcutter.Executions.{DatabaseClock, Run, RunSnapshot, RuntimeNode}
  alias Leafcutter.Executions.RunSnapshot.DefinitionV1
  alias Leafcutter.Repo

  @default_runtime_node_stale_after_ms 45_000

  @typedoc """
  The durable ownership token returned after a successful claim.

  The token identifies the Run, the owning runtime incarnation, and the exact
  fencing generation accepted by the database.
  """
  @type ownership_token :: %{
          required(:run_id) => Run.id(),
          required(:runtime_node_id) => RuntimeNode.id(),
          required(:generation) => pos_integer()
        }

  @typedoc "Error returned when a Run cannot be claimed."
  @type claim_error ::
          :run_not_found
          | :run_not_claimable
          | :runtime_node_not_found
          | :runtime_node_expired
          | :owned_by_active_node
          | Ecto.Changeset.t()

  @typedoc "Error returned when Run ownership cannot be released."
  @type release_error :: :run_not_found | :stale_ownership

  @typedoc "Error returned when a recovery batch cannot be claimed."
  @type recovery_claim_error ::
          :runtime_node_not_found
          | :runtime_node_expired
          | Ecto.Changeset.t()

  @doc """
  Creates a pending Run and freezes its executable definition atomically.

  ## Parameters

  * definition_attrs - The complete logical RunSnapshot definition v1

  ## Returns

  * {:ok, run} after both the Run and its immutable snapshot are committed
  * {:error, changeset} when the definition or a persistence constraint is invalid

  ## Examples

      iex> definition = %{
      ...>   package_version_id: Ecto.UUID.generate(),
      ...>   source: %{
      ...>     ref: "source",
      ...>     contract_version_id: Ecto.UUID.generate(),
      ...>     connection: %{
      ...>       id: Ecto.UUID.generate(),
      ...>       config: %{},
      ...>       secret_version_id: nil
      ...>     }
      ...>   },
      ...>   destinations: [
      ...>     %{
      ...>       ref: "destination",
      ...>       contract_version_id: Ecto.UUID.generate(),
      ...>       connection: %{
      ...>         id: Ecto.UUID.generate(),
      ...>         config: %{},
      ...>         secret_version_id: nil
      ...>       }
      ...>     }
      ...>   ],
      ...>   effective_config: %{}
      ...> }
      iex> {:ok, run} = Leafcutter.Executions.Runs.create(definition)
      iex> run.status
      :pending

  ## Notes

  * The input is the definition itself, not an envelope.
  * The caller cannot set Run identity, lifecycle, ownership, generation, or snapshot version.
  * Definition validation completes before any database write is attempted.
  * Run and RunSnapshot persistence share one transaction and roll back together.
  * Two valid calls create two distinct Runs; idempotency is outside this slice.
  """
  @spec create(map()) :: {:ok, Run.t()} | {:error, Changeset.t()}
  def create(definition_attrs) do
    with {:ok, definition} <- DefinitionV1.validate(definition_attrs) do
      persist_new_run(definition)
    end
  end

  @doc """
  Claims or reclaims a Run for an active runtime node incarnation.

  ## Parameters

  * `run_id` - The identifier of the Run whose ownership will be acquired
  * `runtime_node_id` - The active runtime incarnation requesting ownership

  ## Returns

  * `{:ok, ownership_token}` when the Run is claimed or already belongs to the requester
  * `{:error, :run_not_found}` when the Run does not exist
  * `{:error, :run_not_claimable}` when the Run is in a terminal state
  * `{:error, :runtime_node_not_found}` when the requesting runtime incarnation does not exist
  * `{:error, :runtime_node_expired}` when the requesting runtime incarnation is stale
  * `{:error, :owned_by_active_node}` when another active runtime incarnation owns the Run
  * `{:error, changeset}` when the ownership transition violates a database constraint

  ## Examples

      iex> Leafcutter.Executions.Runs.claim(
      ...>   "00000000-0000-0000-0000-000000000000",
      ...>   Ecto.UUID.generate()
      ...> )
      {:error, :run_not_found}

  ## Notes

  * Only `:pending` and `:running` Runs are claimable.
  * The first claim changes a pending Run to `:running`.
  * Claiming an unowned or stale-owned Run increments `generation`.
  * Repeating a claim from the current active owner is idempotent and preserves `generation`.
  * Another active owner prevents the claim.
  * Runtime liveness and ownership timestamps use the PostgreSQL clock.
  * The Run row is locked while claimability and current ownership are evaluated.
  * Runs created through create/1 always carry a structurally valid snapshot.
  * Legacy pending Runs remain possible until snapshot eligibility is enforced by claim/2.
  """
  @spec claim(Run.id(), RuntimeNode.id()) ::
          {:ok, ownership_token()} | {:error, claim_error()}
  def claim(run_id, runtime_node_id) do
    Repo.transaction(fn ->
      run = lock_claimable_run(run_id)
      database_now = DatabaseClock.now()

      ensure_active_runtime_node(runtime_node_id, database_now)
      claim_locked_run(run, runtime_node_id, database_now)
    end)
  end

  @doc """
  Releases Run ownership when the supplied fencing token is still current.

  ## Parameters

  * `ownership_token` - The Run, runtime incarnation, and generation returned by `claim/2`

  ## Returns

  * `:ok` when current ownership is released
  * `:ok` when the same token already released the Run and no later claim occurred
  * `{:error, :run_not_found}` when the Run does not exist
  * `{:error, :stale_ownership}` when another owner or generation has superseded the token

  ## Examples

      iex> Leafcutter.Executions.Runs.release(%{
      ...>   run_id: "00000000-0000-0000-0000-000000000000",
      ...>   runtime_node_id: Ecto.UUID.generate(),
      ...>   generation: 1
      ...> })
      {:error, :run_not_found}

  ## Notes

  * Release is idempotent only while the Run remains unowned at the token generation.
  * Release does not alter the Run lifecycle status or decrement `generation`.
  * The ownership predicate is applied in the same SQL update that clears the owner.
  * A token becomes stale as soon as another successful claim increments `generation`.
  """
  @spec release(ownership_token()) :: :ok | {:error, release_error()}
  def release(%{
        run_id: run_id,
        runtime_node_id: runtime_node_id,
        generation: generation
      })
      when is_integer(generation) and generation > 0 do
    Repo.transaction(fn ->
      released_at = DatabaseClock.now()

      run_id
      |> current_ownership_query(runtime_node_id, generation)
      |> Repo.update_all(
        set: [
          owner_node_id: nil,
          ownership_acquired_at: nil,
          updated_at: released_at
        ]
      )
      |> classify_release_result(run_id, generation)
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists running Runs currently owned by one runtime node incarnation.

  ## Parameters

  * `runtime_node_id` - The runtime incarnation whose durable ownership tokens will be listed

  ## Returns

  * A list of current ownership tokens ordered by Run identifier
  * An empty list when the runtime incarnation owns no running Runs

  ## Examples

      iex> Leafcutter.Executions.Runs.list_owned_tokens(
      ...>   Ecto.UUID.generate()
      ...> )
      []

  ## Notes

  * Only Runs in the `:running` state are returned.
  * The operation does not validate runtime node liveness.
  * The result is a durable snapshot and may change immediately after the query.
  * Local Registry state does not participate in this lookup.
  """
  @spec list_owned_tokens(RuntimeNode.id()) :: [ownership_token()]
  def list_owned_tokens(runtime_node_id) do
    Run
    |> where(
      [run],
      run.status == :running and
        run.owner_node_id == ^runtime_node_id and
        run.generation > 0
    )
    |> order_by([run], asc: run.id)
    |> select([run], %{
      run_id: run.id,
      runtime_node_id: run.owner_node_id,
      generation: run.generation
    })
    |> Repo.all()
  end

  @doc """
  Claims a bounded batch of running Runs that require recovery.

  ## Parameters

  * `runtime_node_id` - The active runtime incarnation that will acquire the recovered Runs
  * `batch_size` - The maximum number of Runs claimed in one transaction
  * `excluded_run_ids` - Runs temporarily excluded by local startup backoff

  ## Returns

  * `{:ok, ownership_tokens}` after claiming zero or more recoverable Runs
  * `{:error, :runtime_node_not_found}` when the claimant incarnation does not exist
  * `{:error, :runtime_node_expired}` when the claimant incarnation is stale
  * `{:error, changeset}` when an ownership transition violates a database constraint

  ## Examples

      iex> Leafcutter.Executions.Runs.claim_recoverable(
      ...>   Ecto.UUID.generate(),
      ...>   25,
      ...>   []
      ...> )
      {:error, :runtime_node_not_found}

  ## Notes

  * Only Runs already in the `:running` state participate in automatic recovery.
  * Pending Runs remain excluded until snapshot eligibility is added to recovery.
  * Unowned Runs and Runs whose owner heartbeat is older than the stale threshold are eligible.
  * Rows are ordered by oldest `updated_at` and then identifier.
  * `FOR UPDATE SKIP LOCKED` distributes concurrent recovery batches across runtime nodes.
  * Every claimed Run receives a greater fencing generation.
  * Claim and generation updates commit before any local process is started.
  """
  @spec claim_recoverable(
          RuntimeNode.id(),
          pos_integer(),
          [Run.id()]
        ) :: {:ok, [ownership_token()]} | {:error, recovery_claim_error()}
  def claim_recoverable(runtime_node_id, batch_size, excluded_run_ids)
      when is_integer(batch_size) and batch_size > 0 and
             is_list(excluded_run_ids) do
    Repo.transaction(fn ->
      database_now = DatabaseClock.now()
      ensure_active_runtime_node(runtime_node_id, database_now)

      stale_cutoff =
        DateTime.add(
          database_now,
          -runtime_node_stale_after_ms(),
          :millisecond
        )

      stale_cutoff
      |> recoverable_runs_query(batch_size, excluded_run_ids)
      |> Repo.all()
      |> Enum.map(fn run ->
        persist_claim(run, runtime_node_id, database_now)
      end)
    end)
  end

  # OTP 28 loses the MapSet opaqueness when it analyzes Ecto.Multi.new/0.
  # Remove this suppression when elixir-lang/elixir#14576 no longer reproduces.
  @dialyzer {:no_opaque, [persist_new_run: 1]}
  @spec persist_new_run(RunSnapshot.definition()) ::
          {:ok, Run.t()} | {:error, Changeset.t()}
  defp persist_new_run(definition) do
    Multi.new()
    |> Multi.insert(:run, create_run_changeset())
    |> Multi.insert(:snapshot, fn %{run: run} ->
      RunSnapshot.create_changeset(
        %RunSnapshot{},
        %{run_id: run.id, definition: definition}
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{run: run}} ->
        {:ok, run}

      {:error, _operation, %Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  @spec create_run_changeset() :: Changeset.t()
  defp create_run_changeset do
    %Run{}
    |> Changeset.change()
    |> Changeset.foreign_key_constraint(:owner_node_id)
    |> Changeset.check_constraint(:status, name: :runs_status_valid)
    |> Changeset.check_constraint(
      :generation,
      name: :runs_generation_non_negative
    )
    |> Changeset.check_constraint(
      :owner_node_id,
      name: :runs_ownership_fields_consistent
    )
  end

  @spec recoverable_runs_query(
          DateTime.t(),
          pos_integer(),
          [Run.id()]
        ) :: Ecto.Query.t()
  defp recoverable_runs_query(stale_cutoff, batch_size, excluded_run_ids) do
    stale_owner_ids =
      RuntimeNode
      |> where(
        [runtime_node],
        runtime_node.last_heartbeat_at < ^stale_cutoff
      )
      |> select([runtime_node], runtime_node.id)

    Run
    |> where([run], run.status == :running)
    |> where(
      [run],
      is_nil(run.owner_node_id) or
        run.owner_node_id in subquery(stale_owner_ids)
    )
    |> exclude_recovery_runs(excluded_run_ids)
    |> order_by([run], asc: run.updated_at, asc: run.id)
    |> limit(^batch_size)
    |> lock("FOR UPDATE SKIP LOCKED")
  end

  @spec exclude_recovery_runs(Ecto.Query.t(), [Run.id()]) :: Ecto.Query.t()
  defp exclude_recovery_runs(query, []), do: query

  defp exclude_recovery_runs(query, excluded_run_ids) do
    where(
      query,
      [run],
      run.id not in ^excluded_run_ids
    )
  end

  @spec lock_claimable_run(Run.id()) :: Run.t()
  defp lock_claimable_run(run_id) do
    Run
    |> where([run], run.id == ^run_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(:run_not_found)

      %Run{status: status} = run when status in [:pending, :running] ->
        run

      %Run{} ->
        Repo.rollback(:run_not_claimable)
    end
  end

  @spec ensure_active_runtime_node(RuntimeNode.id(), DateTime.t()) :: :ok
  defp ensure_active_runtime_node(runtime_node_id, database_now) do
    case Repo.get(RuntimeNode, runtime_node_id) do
      nil ->
        Repo.rollback(:runtime_node_not_found)

      %RuntimeNode{} = runtime_node ->
        if runtime_node_active?(runtime_node, database_now) do
          :ok
        else
          Repo.rollback(:runtime_node_expired)
        end
    end
  end

  @spec claim_locked_run(Run.t(), RuntimeNode.id(), DateTime.t()) :: ownership_token()
  defp claim_locked_run(%Run{status: :pending} = run, runtime_node_id, database_now) do
    persist_claim(run, runtime_node_id, database_now)
  end

  defp claim_locked_run(%Run{owner_node_id: nil} = run, runtime_node_id, database_now) do
    persist_claim(run, runtime_node_id, database_now)
  end

  defp claim_locked_run(
         %Run{owner_node_id: runtime_node_id} = run,
         runtime_node_id,
         _database_now
       ) do
    build_ownership_token(run)
  end

  defp claim_locked_run(
         %Run{owner_node_id: owner_node_id} = run,
         runtime_node_id,
         database_now
       ) do
    if runtime_node_id_active?(owner_node_id, database_now) do
      Repo.rollback(:owned_by_active_node)
    else
      persist_claim(run, runtime_node_id, database_now)
    end
  end

  @spec persist_claim(Run.t(), RuntimeNode.id(), DateTime.t()) :: ownership_token()
  defp persist_claim(run, runtime_node_id, database_now) do
    changeset =
      run
      |> Changeset.change(%{
        status: :running,
        owner_node_id: runtime_node_id,
        generation: run.generation + 1,
        ownership_acquired_at: database_now
      })
      |> Changeset.foreign_key_constraint(:owner_node_id)
      |> Changeset.check_constraint(:status, name: :runs_status_valid)
      |> Changeset.check_constraint(:generation, name: :runs_generation_non_negative)
      |> Changeset.check_constraint(
        :owner_node_id,
        name: :runs_ownership_fields_consistent
      )

    case Repo.update(changeset) do
      {:ok, run} ->
        build_ownership_token(run)

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @spec build_ownership_token(Run.t()) :: ownership_token()
  defp build_ownership_token(%Run{
         id: run_id,
         owner_node_id: runtime_node_id,
         generation: generation
       })
       when is_binary(run_id) and is_binary(runtime_node_id) and
              is_integer(generation) and generation > 0 do
    %{
      run_id: run_id,
      runtime_node_id: runtime_node_id,
      generation: generation
    }
  end

  @spec runtime_node_id_active?(RuntimeNode.id(), DateTime.t()) :: boolean()
  defp runtime_node_id_active?(runtime_node_id, database_now) do
    case Repo.get(RuntimeNode, runtime_node_id) do
      %RuntimeNode{} = runtime_node -> runtime_node_active?(runtime_node, database_now)
      nil -> false
    end
  end

  @spec runtime_node_active?(RuntimeNode.t(), DateTime.t()) :: boolean()
  defp runtime_node_active?(
         %RuntimeNode{last_heartbeat_at: %DateTime{} = last_heartbeat_at},
         database_now
       ) do
    stale_cutoff =
      DateTime.add(
        database_now,
        -runtime_node_stale_after_ms(),
        :millisecond
      )

    DateTime.compare(last_heartbeat_at, stale_cutoff) in [:gt, :eq]
  end

  defp runtime_node_active?(%RuntimeNode{}, _database_now), do: false

  @spec current_ownership_query(Run.id(), RuntimeNode.id(), pos_integer()) :: Ecto.Query.t()
  defp current_ownership_query(run_id, runtime_node_id, generation) do
    Run
    |> where(
      [run],
      run.id == ^run_id and
        run.owner_node_id == ^runtime_node_id and
        run.generation == ^generation
    )
  end

  @spec classify_release_result(
          {non_neg_integer(), nil | [term()]},
          Run.id(),
          pos_integer()
        ) :: :ok
  defp classify_release_result({1, _returned_rows}, _run_id, _generation), do: :ok

  defp classify_release_result({0, _returned_rows}, run_id, generation) do
    case Repo.get(Run, run_id) do
      nil ->
        Repo.rollback(:run_not_found)

      %Run{owner_node_id: nil, generation: ^generation} ->
        :ok

      %Run{} ->
        Repo.rollback(:stale_ownership)
    end
  end

  @spec runtime_node_stale_after_ms() :: pos_integer()
  defp runtime_node_stale_after_ms do
    configured_value =
      :leafcutter_runtime
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(
        :runtime_node_stale_after_ms,
        @default_runtime_node_stale_after_ms
      )

    case configured_value do
      value when is_integer(value) and value > 0 ->
        value

      invalid_value ->
        raise ArgumentError,
              "expected runtime node stale threshold to be a positive integer, " <>
                "got: #{inspect(invalid_value)}"
    end
  end
end
