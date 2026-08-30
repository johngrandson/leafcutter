defmodule LeafcutterRuntime.Runs do
  @moduledoc """
  Public workflow module for Run resolution and local per-Run supervision.

  EnvironmentDeployment resolution freezes executable state before a Run can
  be claimed. Startup then acquires durable ownership from
  `Leafcutter.Executions.Runs` and only afterward starts the local OTP tree.
  PostgreSQL decides who owns a Run; the local Registry and supervisors
  represent that ownership inside one BEAM node.
  """

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    ContractVersion,
    Packages,
    PackageVersion,
    PackageVersionEndpoint
  }

  alias Leafcutter.Connections
  alias Leafcutter.Connections.{Connection, Secrets, SecretVersion}
  alias Leafcutter.Executions.Run
  alias Leafcutter.Executions.Runs, as: DurableRuns

  alias Leafcutter.Integrations

  alias Leafcutter.Integrations.{
    Deployments,
    EnvironmentDeployment,
    EnvironmentDeploymentBinding,
    Integration
  }

  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo

  alias LeafcutterRuntime.{
    ExecutablePackages,
    NodeHeartbeat,
    RunCoordinator,
    RunDynamicSupervisor,
    RunSupervisor
  }

  @max_local_start_attempts 3
  @local_operation_lock_retry_ms 10

  @typedoc "A local Run supervisor and the durable token retained by its tree."
  @type local_run :: %{
          required(:run_supervisor_pid) => pid(),
          required(:ownership_token) => DurableRuns.ownership_token()
        }

  @typedoc "Error returned after ownership exists but local Run startup fails."
  @type claimed_start_error ::
          {:run_supervisor_start_failed, term()}
          | {:run_supervisor_start_failed, term(), DurableRuns.release_error()}

  @typedoc "Error returned when a Run cannot be claimed or started locally."
  @type start_error :: DurableRuns.claim_error() | claimed_start_error()

  @typedoc "A package-code resolution failure that prevents a new Run."
  @type package_execution_error ::
          :package_not_bound
          | :package_not_installed
          | :manifest_mismatch
          | :invalid_binding

  @typedoc "Semantic reason why an EnvironmentDeployment cannot produce a new Run."
  @type deployment_not_executable_reason ::
          :organization_disabled
          | :environment_disabled
          | :integration_disabled
          | :package_version_mismatch
          | package_execution_error()
          | {:contract_versions_not_executable, nonempty_list(ContractVersion.id())}
          | {:binding_mismatch,
             %{
               required(:missing_refs) => [String.t()],
               required(:unexpected_refs) => [String.t()]
             }}
          | {:connection_not_found, Connection.id()}
          | {:connection_disabled, Connection.id()}
          | {:connection_scope_mismatch, Connection.id()}
          | {:connector_mismatch, String.t()}
          | {:secret_version_not_found, SecretVersion.id()}
          | {:secret_version_scope_mismatch, SecretVersion.id()}

  @typedoc "Error returned while resolving an EnvironmentDeployment into a new Run."
  @type create_from_deployment_error ::
          :environment_deployment_not_found
          | {:environment_deployment_not_executable, deployment_not_executable_reason()}
          | Changeset.t()

  @doc """
  Creates a pending Run from one persisted EnvironmentDeployment.

  ## Parameters

  * `environment_deployment_id` - The deployment whose current executable state is frozen

  ## Returns

  * `{:ok, run}` after the Run and its immutable snapshot commit atomically
  * `{:error, :environment_deployment_not_found}` when the deployment does not exist
  * `{:error, {:environment_deployment_not_executable, reason}}` when an
    authority is disabled, semantically incompatible, or lacks compiled package code
  * `{:error, changeset}` when the final RunSnapshot definition is structurally invalid

  ## Examples

  Given a persisted, executable EnvironmentDeployment:

      iex> {:ok, run} =
      ...>   LeafcutterRuntime.Runs.create_from_deployment(deployment.id)

      iex> run.status
      :pending

      iex> LeafcutterRuntime.Runs.create_from_deployment(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :environment_deployment_not_found}

  ## Notes

  * One outer Repo transaction owns discovery, authority locks, resolution, and Run creation.
  * Mutable authorities are locked in the ratified deterministic order.
  * Catalog projections and SecretVersion identities are read without locks because they are immutable.
  * ContractVersion executability is revalidated from the immutable PackageVersion projection.
  * Package manifest, inventory, and compiled binding compatibility are revalidated before persistence.
  * Effective config recursively merges promotable config with local config taking precedence.
  * Connection config and the exact current SecretVersion identifier are copied into definition v1.
  * The workflow does not start a local Run tree or perform any external effect.
  * Repeating a successful call creates another distinct Run.
  """
  @spec create_from_deployment(EnvironmentDeployment.id()) ::
          {:ok, Run.t()} | {:error, create_from_deployment_error()}
  def create_from_deployment(environment_deployment_id) do
    Repo.transaction(fn ->
      case resolve_and_create_run(environment_deployment_id) do
        {:ok, run} -> run
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec resolve_and_create_run(EnvironmentDeployment.id()) ::
          {:ok, Run.t()} | {:error, create_from_deployment_error()}
  defp resolve_and_create_run(environment_deployment_id) do
    with {:ok, resolution_scope} <-
           fetch_resolution_scope(environment_deployment_id),
         {:ok, _active_scope} <- lock_active_scope(resolution_scope),
         {:ok, integration} <- lock_active_integration(resolution_scope),
         {:ok, deployment} <-
           lock_deployment_for_resolution(environment_deployment_id),
         :ok <- ensure_resolution_scope(deployment, resolution_scope),
         {:ok, connections} <- lock_active_connections(deployment),
         {:ok, package_version} <-
           fetch_package_version(deployment.package_version_id),
         :ok <- validate_package_version(package_version, integration),
         :ok <- validate_contract_versions_executable(package_version),
         :ok <- validate_binding_refs(package_version, deployment.bindings),
         :ok <-
           validate_connector_compatibility(
             package_version,
             deployment.bindings,
             connections
           ),
         :ok <- validate_secret_versions(connections, resolution_scope),
         :ok <- resolve_executable_package(package_version) do
      definition =
        build_definition(
          deployment,
          package_version,
          connections
        )

      DurableRuns.create(definition)
    end
  end

  @spec fetch_resolution_scope(EnvironmentDeployment.id()) ::
          {:ok, Deployments.resolution_scope()}
          | {:error, :environment_deployment_not_found}
  defp fetch_resolution_scope(environment_deployment_id) do
    case Deployments.fetch_resolution_scope(environment_deployment_id) do
      {:ok, resolution_scope} -> {:ok, resolution_scope}
      {:error, :not_found} -> {:error, :environment_deployment_not_found}
    end
  end

  @spec lock_active_scope(Deployments.resolution_scope()) ::
          {:ok, Environments.active_scope()}
          | {:error,
             {:environment_deployment_not_executable,
              :organization_disabled | :environment_disabled}}
  defp lock_active_scope(resolution_scope) do
    case Environments.lock_active_scope(
           resolution_scope.organization_id,
           resolution_scope.environment_id
         ) do
      {:ok, active_scope} ->
        {:ok, active_scope}

      {:error, reason}
      when reason in [:organization_disabled, :environment_disabled] ->
        not_executable(reason)

      {:error, reason} ->
        raise_unexpected_authority_state!(:environment_scope, reason)
    end
  end

  @spec lock_active_integration(Deployments.resolution_scope()) ::
          {:ok, Integration.t()}
          | {:error, {:environment_deployment_not_executable, :integration_disabled}}
  defp lock_active_integration(resolution_scope) do
    case Integrations.lock_active(
           resolution_scope.integration_id,
           resolution_scope.organization_id
         ) do
      {:ok, integration} ->
        {:ok, integration}

      {:error, :integration_disabled} ->
        not_executable(:integration_disabled)

      {:error, reason} ->
        raise_unexpected_authority_state!(:integration, reason)
    end
  end

  @spec lock_deployment_for_resolution(EnvironmentDeployment.id()) ::
          {:ok, EnvironmentDeployment.t()}
          | {:error, :environment_deployment_not_found}
  defp lock_deployment_for_resolution(environment_deployment_id) do
    case Deployments.lock_for_resolution(environment_deployment_id) do
      {:ok, deployment} -> {:ok, deployment}
      {:error, :not_found} -> {:error, :environment_deployment_not_found}
      {:error, reason} -> raise_unexpected_authority_state!(:deployment, reason)
    end
  end

  @spec ensure_resolution_scope(
          EnvironmentDeployment.t(),
          Deployments.resolution_scope()
        ) :: :ok
  defp ensure_resolution_scope(deployment, resolution_scope) do
    if deployment.organization_id == resolution_scope.organization_id and
         deployment.environment_id == resolution_scope.environment_id and
         deployment.integration_id == resolution_scope.integration_id do
      :ok
    else
      raise "EnvironmentDeployment immutable resolution scope changed during resolution"
    end
  end

  @spec lock_active_connections(EnvironmentDeployment.t()) ::
          {:ok, [Connection.t()]}
          | {:error,
             {:environment_deployment_not_executable,
              {:connection_not_found, Connection.id()}
              | {:connection_disabled, Connection.id()}
              | {:connection_scope_mismatch, Connection.id()}}}
  defp lock_active_connections(deployment) do
    connection_ids = Enum.map(deployment.bindings, & &1.connection_id)

    case Connections.lock_active(
           connection_ids,
           deployment.organization_id,
           deployment.environment_id
         ) do
      {:ok, connections} ->
        {:ok, connections}

      {:error, reason} when is_tuple(reason) ->
        not_executable(reason)

      {:error, reason} ->
        raise_unexpected_authority_state!(:connections, reason)
    end
  end

  @spec fetch_package_version(PackageVersion.id()) ::
          {:ok, PackageVersion.t()}
  defp fetch_package_version(package_version_id) do
    case Packages.get_version(package_version_id) do
      {:ok, package_version} ->
        {:ok, package_version}

      {:error, :not_found} ->
        raise_unexpected_authority_state!(
          :package_version,
          :not_found
        )
    end
  end

  @spec validate_package_version(PackageVersion.t(), Integration.t()) ::
          :ok
          | {:error, {:environment_deployment_not_executable, :package_version_mismatch}}
  defp validate_package_version(package_version, integration) do
    if package_version.package_id == integration.package_id do
      :ok
    else
      not_executable(:package_version_mismatch)
    end
  end

  @spec validate_contract_versions_executable(PackageVersion.t()) ::
          :ok
          | {:error,
             {:environment_deployment_not_executable,
              {:contract_versions_not_executable, nonempty_list(ContractVersion.id())}}}
  defp validate_contract_versions_executable(package_version) do
    contract_version_ids =
      package_version.endpoints
      |> Enum.flat_map(fn
        %PackageVersionEndpoint{
          contract_version_id: contract_version_id,
          contract_version: %ContractVersion{schema: nil}
        } ->
          [contract_version_id]

        _executable_endpoint ->
          []
      end)
      |> Enum.uniq()
      |> Enum.sort()

    case contract_version_ids do
      [] ->
        :ok

      contract_version_ids ->
        not_executable({:contract_versions_not_executable, contract_version_ids})
    end
  end

  @spec validate_binding_refs(
          PackageVersion.t(),
          [EnvironmentDeploymentBinding.t()]
        ) ::
          :ok
          | {:error,
             {:environment_deployment_not_executable,
              {:binding_mismatch,
               %{
                 required(:missing_refs) => [String.t()],
                 required(:unexpected_refs) => [String.t()]
               }}}}
  defp validate_binding_refs(package_version, bindings) do
    expected_refs = MapSet.new(package_version.endpoints, & &1.ref)
    actual_refs = MapSet.new(bindings, & &1.ref)

    missing_refs =
      expected_refs
      |> MapSet.difference(actual_refs)
      |> Enum.sort()

    unexpected_refs =
      actual_refs
      |> MapSet.difference(expected_refs)
      |> Enum.sort()

    if missing_refs == [] and unexpected_refs == [] do
      :ok
    else
      not_executable(
        {:binding_mismatch,
         %{
           missing_refs: missing_refs,
           unexpected_refs: unexpected_refs
         }}
      )
    end
  end

  @spec validate_connector_compatibility(
          PackageVersion.t(),
          [EnvironmentDeploymentBinding.t()],
          [Connection.t()]
        ) ::
          :ok
          | {:error, {:environment_deployment_not_executable, {:connector_mismatch, String.t()}}}
  defp validate_connector_compatibility(
         package_version,
         bindings,
         connections
       ) do
    endpoints_by_ref = Map.new(package_version.endpoints, &{&1.ref, &1})
    connections_by_id = Map.new(connections, &{&1.id, &1})

    bindings
    |> Enum.sort_by(& &1.ref)
    |> Enum.find_value(:ok, fn binding ->
      endpoint = Map.fetch!(endpoints_by_ref, binding.ref)
      connection = Map.fetch!(connections_by_id, binding.connection_id)

      if endpoint_connector_id(endpoint) == connection.connector_id do
        false
      else
        not_executable({:connector_mismatch, binding.ref})
      end
    end)
  end

  @spec endpoint_connector_id(PackageVersionEndpoint.t()) :: Ecto.UUID.t()
  defp endpoint_connector_id(endpoint) do
    endpoint.operation.connector_version.connector_id
  end

  @spec validate_secret_versions(
          [Connection.t()],
          Deployments.resolution_scope()
        ) ::
          :ok
          | {:error,
             {:environment_deployment_not_executable,
              {:secret_version_not_found, SecretVersion.id()}
              | {:secret_version_scope_mismatch, SecretVersion.id()}}}
  defp validate_secret_versions(connections, resolution_scope) do
    secret_version_ids =
      connections
      |> Enum.map(& &1.secret_version_id)
      |> Enum.reject(&is_nil/1)

    case Secrets.fetch_versions(
           secret_version_ids,
           resolution_scope.organization_id,
           resolution_scope.environment_id
         ) do
      {:ok, _secret_versions} ->
        :ok

      {:error, reason} ->
        not_executable(reason)
    end
  end

  @spec resolve_executable_package(PackageVersion.t()) ::
          :ok
          | {:error,
             {:environment_deployment_not_executable, package_execution_error()}}
  defp resolve_executable_package(package_version) do
    case ExecutablePackages.resolve_projection(package_version) do
      {:ok, _binding} ->
        :ok

      {:error, reason}
      when reason in [
             :package_not_bound,
             :package_not_installed,
             :manifest_mismatch,
             :invalid_binding
           ] ->
        not_executable(reason)
    end
  end

  @spec build_definition(
          EnvironmentDeployment.t(),
          PackageVersion.t(),
          [Connection.t()]
        ) :: map()
  defp build_definition(deployment, package_version, connections) do
    source = Enum.find(package_version.endpoints, &(&1.role == :source))

    destinations =
      package_version.endpoints
      |> Enum.filter(&(&1.role == :destination))
      |> Enum.sort_by(& &1.position)

    bindings_by_ref = Map.new(deployment.bindings, &{&1.ref, &1})
    connections_by_id = Map.new(connections, &{&1.id, &1})

    %{
      package_version_id: deployment.package_version_id,
      source:
        build_definition_endpoint(
          source,
          bindings_by_ref,
          connections_by_id
        ),
      destinations:
        Enum.map(destinations, fn endpoint ->
          build_definition_endpoint(
            endpoint,
            bindings_by_ref,
            connections_by_id
          )
        end),
      effective_config:
        deep_merge(
          deployment.promotable_config,
          deployment.local_config
        )
    }
  end

  @spec build_definition_endpoint(
          PackageVersionEndpoint.t(),
          %{String.t() => EnvironmentDeploymentBinding.t()},
          %{Connection.id() => Connection.t()}
        ) :: map()
  defp build_definition_endpoint(
         endpoint,
         bindings_by_ref,
         connections_by_id
       ) do
    binding = Map.fetch!(bindings_by_ref, endpoint.ref)
    connection = Map.fetch!(connections_by_id, binding.connection_id)

    %{
      ref: endpoint.ref,
      contract_version_id: endpoint.contract_version_id,
      connection: %{
        id: connection.id,
        config: connection.config,
        secret_version_id: connection.secret_version_id
      }
    }
  end

  @spec deep_merge(map(), map()) :: map()
  defp deep_merge(promotable_config, local_config) do
    Map.merge(
      promotable_config,
      local_config,
      fn _key, promotable_value, local_value ->
        if is_map(promotable_value) and not is_struct(promotable_value) and
             is_map(local_value) and not is_struct(local_value) do
          deep_merge(promotable_value, local_value)
        else
          local_value
        end
      end
    )
  end

  @spec not_executable(deployment_not_executable_reason()) ::
          {:error, {:environment_deployment_not_executable, deployment_not_executable_reason()}}
  defp not_executable(reason) do
    {:error, {:environment_deployment_not_executable, reason}}
  end

  @spec raise_unexpected_authority_state!(atom(), term()) :: no_return()
  defp raise_unexpected_authority_state!(authority, reason) do
    raise "unexpected #{authority} authority state during EnvironmentDeployment resolution: " <>
            inspect(reason)
  end

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

  Given a structurally valid definition like the one shown in
  `Leafcutter.Executions.Runs.create/1`:

      iex> {:ok, run} =
      ...>   Leafcutter.Executions.Runs.create(valid_definition)

      iex> {:ok, run_supervisor_pid} =
      ...>   LeafcutterRuntime.Runs.start(run.id)

      iex> is_pid(run_supervisor_pid)
      true

      iex> LeafcutterRuntime.Runs.stop(run.id)
      :ok

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
  * Local start and stop operations are serialized per Run identifier.
  * This workflow does not create Runs or perform automatic recovery scanning itself.
  """
  @spec start(Run.id()) :: {:ok, pid()} | {:error, start_error()}
  def start(run_id) do
    with_local_run_operation(run_id, fn -> start_locked(run_id) end)
  end

  @spec start_locked(Run.id()) :: {:ok, pid()} | {:error, start_error()}
  defp start_locked(run_id) do
    runtime_node_id = NodeHeartbeat.runtime_node_id()

    case DurableRuns.claim(run_id, runtime_node_id) do
      {:ok, ownership_token} ->
        start_claimed_locked(ownership_token)

      {:error, reason} ->
        terminate_registered_tree(run_id)
        {:error, reason}
    end
  end

  @doc """
  Starts or reconciles a local Run tree from an ownership token already acquired.

  ## Parameters

  * `ownership_token` - The durable token committed before local startup

  ## Returns

  * `{:ok, run_supervisor_pid}` when a new local Run tree starts
  * `{:ok, run_supervisor_pid}` when the same token is already represented locally
  * `{:error, {:run_supervisor_start_failed, reason}}` when local startup fails and ownership is released
  * `{:error, {:run_supervisor_start_failed, reason, release_error}}` when startup and ownership cleanup both fail

  ## Examples

  Given a structurally valid definition like the one shown in
  `Leafcutter.Executions.Runs.create/1`:

      iex> {:ok, run} =
      ...>   Leafcutter.Executions.Runs.create(valid_definition)

      iex> runtime_node_id =
      ...>   LeafcutterRuntime.NodeHeartbeat.runtime_node_id()

      iex> {:ok, _runtime_node} =
      ...>   Leafcutter.Executions.Nodes.heartbeat(
      ...>     runtime_node_id,
      ...>     "start-claimed-example@host"
      ...>   )

      iex> {:ok, ownership_token} =
      ...>   Leafcutter.Executions.Runs.claim(run.id, runtime_node_id)

      iex> {:ok, run_supervisor_pid} =
      ...>   LeafcutterRuntime.Runs.start_claimed(ownership_token)

      iex> is_pid(run_supervisor_pid)
      true

      iex> LeafcutterRuntime.Runs.stop(run.id)
      :ok

      iex> function_exported?(
      ...>   LeafcutterRuntime.Runs,
      ...>   :start_claimed,
      ...>   1
      ...> )
      true

  ## Notes

  * This operation does not perform another durable claim.
  * Recovery uses it only after a token has committed in PostgreSQL.
  * A locally registered older generation is terminated before the supplied token starts.
  * Failed startup releases the supplied token unless another matching local tree won the race.
  * Startup is serialized with explicit local start and stop operations for the same Run.
  """
  @spec start_claimed(DurableRuns.ownership_token()) ::
          {:ok, pid()} | {:error, claimed_start_error()}
  def start_claimed(ownership_token) do
    with_local_run_operation(
      ownership_token.run_id,
      fn -> start_claimed_locked(ownership_token) end
    )
  end

  @spec start_claimed_locked(DurableRuns.ownership_token()) ::
          {:ok, pid()} | {:error, claimed_start_error()}
  defp start_claimed_locked(ownership_token) do
    ensure_local_tree(ownership_token)
  end

  @doc """
  Lists all live per-Run supervision trees registered on the local node.

  ## Returns

  * A list containing each local Run supervisor and its retained ownership token
  * An empty list when no Run tree is active locally

  ## Examples

      iex> is_list(LeafcutterRuntime.Runs.list_local())
      true

  ## Notes

  * The result is derived from the local DynamicSupervisor and Registry.
  * Non-Run children and dead processes observed during a race are omitted.
  * PostgreSQL remains authoritative even when a local tree is listed.
  """
  @spec list_local() :: [local_run()]
  def list_local do
    RunDynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(&local_run_from_child/1)
    |> Enum.sort_by(fn local_run ->
      local_run.ownership_token.run_id
    end)
  end

  @spec local_run_from_child(tuple()) :: [local_run()]
  defp local_run_from_child({_child_id, run_supervisor_pid, :supervisor, _modules})
       when is_pid(run_supervisor_pid) do
    with [run_id] when is_binary(run_id) <-
           Registry.keys(
             LeafcutterRuntime.RunRegistry,
             run_supervisor_pid
           ),
         {:ok, local_run} <- lookup(run_id) do
      [local_run]
    else
      _not_local_run -> []
    end
  end

  defp local_run_from_child(_other_child), do: []

  @doc """
  Returns the local supervision tree registered for a Run.

  ## Parameters

  * `run_id` - The identifier used as the local Run Registry key

  ## Returns

  * `{:ok, local_run}` when a live Run supervisor is registered locally
  * `:error` when the Run has no live local supervision tree

  ## Examples

  Given a structurally valid definition like the one shown in
  `Leafcutter.Executions.Runs.create/1`:

      iex> {:ok, run} =
      ...>   Leafcutter.Executions.Runs.create(valid_definition)

      iex> {:ok, _run_supervisor_pid} =
      ...>   LeafcutterRuntime.Runs.start(run.id)

      iex> {:ok, local_run} =
      ...>   LeafcutterRuntime.Runs.lookup(run.id)

      iex> local_run.ownership_token.run_id == run.id
      true

      iex> LeafcutterRuntime.Runs.stop(run.id)
      :ok

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
  * Local start and stop operations are serialized per Run identifier.
  * A later start must perform a fresh durable claim.
  """
  @spec stop(Run.id()) :: :ok | {:error, DurableRuns.release_error()}
  def stop(run_id) do
    with_local_run_operation(run_id, fn -> stop_locked(run_id) end)
  end

  @spec stop_locked(Run.id()) :: :ok | {:error, DurableRuns.release_error()}
  defp stop_locked(run_id) do
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
          {:ok, pid()} | {:error, claimed_start_error()}
  defp ensure_local_tree(ownership_token) do
    ensure_local_tree(ownership_token, @max_local_start_attempts)
  end

  @spec ensure_local_tree(
          DurableRuns.ownership_token(),
          non_neg_integer()
        ) :: {:ok, pid()} | {:error, claimed_start_error()}
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
        ) :: {:ok, pid()} | {:error, claimed_start_error()}
  defp start_local_tree(ownership_token, attempts_remaining) do
    child_spec = {RunSupervisor, ownership_token}

    case start_dynamic_child(child_spec) do
      {:ok, run_supervisor_pid} ->
        {:ok, run_supervisor_pid}

      {:ok, run_supervisor_pid, _info} ->
        {:ok, run_supervisor_pid}

      :ignore ->
        reconcile_start_failure(ownership_token, :ignore)

      {:error, {:already_started, _run_supervisor_pid}} ->
        ensure_local_tree(ownership_token, attempts_remaining - 1)

      {:exit, reason} ->
        reconcile_start_failure(ownership_token, {:exit, reason})

      {:error, reason} ->
        reconcile_start_failure(ownership_token, reason)
    end
  end

  @spec start_dynamic_child({module(), DurableRuns.ownership_token()}) ::
          DynamicSupervisor.on_start_child() | {:exit, term()}
  defp start_dynamic_child(child_spec) do
    DynamicSupervisor.start_child(
      RunDynamicSupervisor,
      child_spec
    )
  catch
    :exit, reason -> {:exit, reason}
  end

  @spec reconcile_start_failure(
          DurableRuns.ownership_token(),
          term()
        ) :: {:ok, pid()} | {:error, claimed_start_error()}
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
        ) :: {:ok, pid()} | {:error, claimed_start_error()}
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

  @spec with_local_run_operation(Run.id(), (-> result)) :: result when result: term()
  defp with_local_run_operation(run_id, operation) do
    operation_lock_key = {:run_operation, run_id}

    case Registry.register(
           LeafcutterRuntime.RunRegistry,
           operation_lock_key,
           :local_operation
         ) do
      {:ok, _owner} ->
        try do
          operation.()
        after
          Registry.unregister(
            LeafcutterRuntime.RunRegistry,
            operation_lock_key
          )
        end

      {:error, {:already_registered, _owner}} ->
        receive do
        after
          @local_operation_lock_retry_ms ->
            with_local_run_operation(run_id, operation)
        end
    end
  end
end
