defmodule Leafcutter.Integrations.Deployments do
  @moduledoc """
  Public capability for complete EnvironmentDeployment state.

  Creation and replacement validate mutable authorities under deterministic
  locks, read immutable Catalog projections, and persist all endpoint bindings
  atomically. Effective config remains a runtime resolution concern.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{Packages, PackageVersion, PackageVersionEndpoint}
  alias Leafcutter.Connections
  alias Leafcutter.Connections.Connection

  alias Leafcutter.Integrations

  alias Leafcutter.Integrations.{
    EnvironmentDeployment,
    EnvironmentDeploymentBinding,
    Integration
  }

  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo

  @typedoc "Attributes that bind one PackageVersion endpoint ref to a Connection."
  @type binding_attrs ::
          %{
            required(:ref) => String.t(),
            required(:connection_id) => Connection.id()
          }
          | %{required(String.t()) => String.t()}

  @typedoc "Attributes accepted when creating a complete EnvironmentDeployment."
  @type create_attrs ::
          %{
            required(:organization_id) => Ecto.UUID.t(),
            required(:environment_id) => Ecto.UUID.t(),
            required(:integration_id) => Integration.id(),
            required(:package_version_id) => PackageVersion.id(),
            optional(:promotable_config) => map(),
            optional(:local_config) => map(),
            required(:bindings) => [binding_attrs()]
          }
          | %{required(String.t()) => String.t() | map() | [binding_attrs()]}

  @typedoc "Attributes accepted when replacing complete mutable deployment state."
  @type replace_attrs ::
          %{
            required(:package_version_id) => PackageVersion.id(),
            optional(:promotable_config) => map(),
            optional(:local_config) => map(),
            required(:bindings) => [binding_attrs()]
          }
          | %{required(String.t()) => String.t() | map() | [binding_attrs()]}

  @typedoc "Deterministic mismatch between PackageVersion endpoint refs and bindings."
  @type binding_mismatch ::
          {:binding_mismatch,
           %{
             missing_refs: [String.t()],
             unexpected_refs: [String.t()]
           }}

  @typedoc "Authority or semantic error returned while validating deployment state."
  @type validation_error ::
          Environments.active_scope_state_error()
          | Integrations.active_integration_state_error()
          | :package_version_not_found
          | :package_version_mismatch
          | binding_mismatch()
          | {:connection_not_found, Connection.id()}
          | {:connection_disabled, Connection.id()}
          | {:connection_scope_mismatch, Connection.id()}
          | {:connector_mismatch, String.t()}
          | Changeset.t()

  @typedoc "Error returned while creating an EnvironmentDeployment."
  @type create_error :: validation_error()

  @typedoc "Error returned while replacing an EnvironmentDeployment."
  @type replace_error :: :not_found | validation_error()

  @doc """
  Creates one complete EnvironmentDeployment and all endpoint bindings.

  ## Parameters

  * `attrs` - Scope, Integration, PackageVersion, separated config, and complete bindings

  ## Returns

  * `{:ok, deployment}` with bindings loaded when the complete state is persisted
  * `{:error, reason}` when an authority is absent, incompatible, or disabled
  * `{:error, {:binding_mismatch, details}}` when endpoint coverage is incomplete
  * `{:error, changeset}` when an attribute or database constraint is invalid

  ## Examples

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Integrations.Deployments.create(%{})
      ...> )
      true

  ## Notes

  * At most one deployment exists per Integration and Environment.
  * Missing config fields become empty JSON objects.
  * Bindings must match every PackageVersion endpoint ref exactly.
  * Connections are locked once in deterministic identifier order.
  * Effective config, SecretVersion freezing, and Run creation remain outside this capability.
  """
  @spec create(create_attrs()) ::
          {:ok, EnvironmentDeployment.t()} | {:error, create_error()}
  def create(attrs) do
    deployment = %EnvironmentDeployment{id: Ecto.UUID.generate()}
    normalized_attrs = put_config_defaults(attrs)
    changeset = EnvironmentDeployment.create_changeset(deployment, normalized_attrs)

    with {:ok, binding_changesets} <-
           prepare_bindings(changeset, deployment.id, normalized_attrs) do
      create_with_locked_authorities(changeset, binding_changesets)
    end
  end

  @doc """
  Fetches an EnvironmentDeployment with its complete binding set.

  ## Parameters

  * `id` - The EnvironmentDeployment identifier to fetch

  ## Returns

  * `{:ok, deployment}` with bindings ordered by ref
  * `{:error, :not_found}` when no EnvironmentDeployment has the identifier

  ## Examples

      iex> Leafcutter.Integrations.Deployments.get(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * Parent authorities and Catalog projections are not preloaded.
  * Lookup does not revalidate lifecycle or semantic compatibility.
  * Bindings contain only ref and Connection identity.
  """
  @spec get(EnvironmentDeployment.id()) ::
          {:ok, EnvironmentDeployment.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(EnvironmentDeployment, id) do
      %EnvironmentDeployment{} = deployment ->
        {:ok, load_bindings(deployment)}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Replaces PackageVersion, separated config, and all bindings atomically.

  ## Parameters

  * `id` - The EnvironmentDeployment identifier to replace
  * `attrs` - Complete replacement PackageVersion, config, and binding state

  ## Returns

  * `{:ok, deployment}` with the replacement bindings loaded
  * `{:error, :not_found}` when the EnvironmentDeployment does not exist
  * `{:error, reason}` when an authority is absent, incompatible, or disabled
  * `{:error, {:binding_mismatch, details}}` when endpoint coverage is incomplete
  * `{:error, changeset}` when replacement state or a database constraint is invalid

  ## Examples

      iex> Leafcutter.Integrations.Deployments.replace(
      ...>   "00000000-0000-0000-0000-000000000000",
      ...>   %{}
      ...> )
      {:error, :not_found}

  ## Notes

  * Replacement is complete rather than patch-based.
  * Missing config fields become empty JSON objects instead of preserving old values.
  * Organization, Environment, and Integration identity are immutable and ignored in attrs.
  * The deployment row is locked before its bindings and Connections are read.
  * Any failure rolls back PackageVersion, config, and every binding change.
  """
  @spec replace(EnvironmentDeployment.id(), replace_attrs()) ::
          {:ok, EnvironmentDeployment.t()} | {:error, replace_error()}
  def replace(id, attrs) do
    with {:ok, unlocked_deployment} <- fetch_deployment(id) do
      normalized_attrs = put_config_defaults(attrs)

      changeset =
        EnvironmentDeployment.replace_changeset(
          unlocked_deployment,
          normalized_attrs
        )
        |> require_attribute(normalized_attrs, :package_version_id)

      with {:ok, binding_changesets} <-
             prepare_bindings(changeset, id, normalized_attrs) do
        replace_with_locked_authorities(
          unlocked_deployment,
          normalized_attrs,
          binding_changesets
        )
      end
    end
  end

  @spec create_with_locked_authorities(
          Changeset.t(),
          [Changeset.t()]
        ) :: {:ok, EnvironmentDeployment.t()} | {:error, create_error()}
  defp create_with_locked_authorities(
         %Changeset{valid?: false} = changeset,
         _binding_changesets
       ) do
    {:error, changeset}
  end

  defp create_with_locked_authorities(changeset, binding_changesets) do
    organization_id = Changeset.fetch_field!(changeset, :organization_id)
    environment_id = Changeset.fetch_field!(changeset, :environment_id)
    integration_id = Changeset.fetch_field!(changeset, :integration_id)
    package_version_id = Changeset.fetch_field!(changeset, :package_version_id)

    Repo.transaction(fn ->
      with {:ok, _scope} <-
             Environments.lock_active_scope(
               organization_id,
               environment_id
             ),
           {:ok, integration} <-
             Integrations.lock_active(integration_id, organization_id),
           {:ok, connections} <-
             lock_connections(
               binding_changesets,
               organization_id,
               environment_id
             ),
           {:ok, package_version} <-
             fetch_package_version(package_version_id),
           :ok <- validate_package_version(package_version, integration),
           :ok <- validate_binding_refs(package_version, binding_changesets),
           :ok <-
             validate_connector_compatibility(
               package_version,
               binding_changesets,
               connections
             ) do
        deployment = insert_deployment_or_rollback(changeset)
        bindings = insert_bindings_or_rollback(binding_changesets)

        attach_bindings(deployment, bindings)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec replace_with_locked_authorities(
          EnvironmentDeployment.t(),
          map(),
          [Changeset.t()]
        ) :: {:ok, EnvironmentDeployment.t()} | {:error, replace_error()}
  defp replace_with_locked_authorities(
         unlocked_deployment,
         attrs,
         binding_changesets
       ) do
    Repo.transaction(fn ->
      with {:ok, _scope} <-
             Environments.lock_active_scope(
               unlocked_deployment.organization_id,
               unlocked_deployment.environment_id
             ),
           {:ok, integration} <-
             Integrations.lock_active(
               unlocked_deployment.integration_id,
               unlocked_deployment.organization_id
             ),
           {:ok, deployment} <- lock_deployment(unlocked_deployment.id),
           {:ok, changeset} <- validate_replacement(deployment, attrs),
           package_version_id =
             Changeset.fetch_field!(changeset, :package_version_id),
           {:ok, connections} <-
             lock_connections(
               binding_changesets,
               deployment.organization_id,
               deployment.environment_id
             ),
           {:ok, package_version} <-
             fetch_package_version(package_version_id),
           :ok <- validate_package_version(package_version, integration),
           :ok <- validate_binding_refs(package_version, binding_changesets),
           :ok <-
             validate_connector_compatibility(
               package_version,
               binding_changesets,
               connections
             ) do
        updated_deployment = update_deployment_or_rollback(changeset)
        delete_bindings(deployment.id)
        bindings = insert_bindings_or_rollback(binding_changesets)

        attach_bindings(updated_deployment, bindings)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec prepare_bindings(
          Changeset.t(),
          EnvironmentDeployment.id(),
          map()
        ) :: {:ok, [Changeset.t()]} | {:error, Changeset.t()}
  defp prepare_bindings(parent_changeset, deployment_id, attrs) do
    case attribute(attrs, :bindings, :missing) do
      :missing ->
        {:error,
         Changeset.add_error(
           parent_changeset,
           :bindings,
           "is required",
           validation: :required
         )}

      binding_attrs when is_list(binding_attrs) ->
        build_binding_changesets(
          parent_changeset,
          deployment_id,
          binding_attrs
        )

      _invalid ->
        {:error,
         Changeset.add_error(
           parent_changeset,
           :bindings,
           "must be a list",
           validation: :list
         )}
    end
  end

  @spec build_binding_changesets(
          Changeset.t(),
          EnvironmentDeployment.id(),
          [term()]
        ) :: {:ok, [Changeset.t()]} | {:error, Changeset.t()}
  defp build_binding_changesets(
         parent_changeset,
         deployment_id,
         binding_attrs
       ) do
    binding_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, changesets} ->
      reduce_binding_attrs(
        attrs,
        changesets,
        parent_changeset,
        deployment_id
      )
    end)
    |> case do
      {:ok, changesets} -> {:ok, Enum.reverse(changesets)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec reduce_binding_attrs(
          term(),
          [Changeset.t()],
          Changeset.t(),
          EnvironmentDeployment.id()
        ) ::
          {:cont, {:ok, [Changeset.t()]}}
          | {:halt, {:error, Changeset.t()}}
  defp reduce_binding_attrs(
         attrs,
         changesets,
         _parent_changeset,
         deployment_id
       )
       when is_map(attrs) do
    changeset =
      EnvironmentDeploymentBinding.create_changeset(
        %EnvironmentDeploymentBinding{},
        %{
          environment_deployment_id: deployment_id,
          ref: attribute(attrs, :ref),
          connection_id: attribute(attrs, :connection_id)
        }
      )

    if changeset.valid? do
      {:cont, {:ok, [changeset | changesets]}}
    else
      {:halt, {:error, changeset}}
    end
  end

  defp reduce_binding_attrs(
         _attrs,
         _changesets,
         parent_changeset,
         _deployment_id
       ) do
    {:halt,
     {:error,
      Changeset.add_error(
        parent_changeset,
        :bindings,
        "must contain only maps",
        validation: :map
      )}}
  end

  @spec fetch_package_version(PackageVersion.id()) ::
          {:ok, PackageVersion.t()} | {:error, :package_version_not_found}
  defp fetch_package_version(id) do
    case Packages.get_version(id) do
      {:ok, package_version} -> {:ok, package_version}
      {:error, :not_found} -> {:error, :package_version_not_found}
    end
  end

  @spec validate_package_version(PackageVersion.t(), Integration.t()) ::
          :ok | {:error, :package_version_mismatch}
  defp validate_package_version(package_version, integration) do
    if package_version.package_id == integration.package_id do
      :ok
    else
      {:error, :package_version_mismatch}
    end
  end

  @spec validate_binding_refs(PackageVersion.t(), [Changeset.t()]) ::
          :ok | {:error, binding_mismatch()}
  defp validate_binding_refs(package_version, binding_changesets) do
    expected_refs =
      package_version.endpoints
      |> Enum.map(& &1.ref)
      |> MapSet.new()

    actual_refs =
      binding_changesets
      |> Enum.map(&Changeset.fetch_field!(&1, :ref))
      |> MapSet.new()

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
      {:error,
       {:binding_mismatch,
        %{
          missing_refs: missing_refs,
          unexpected_refs: unexpected_refs
        }}}
    end
  end

  @spec lock_connections(
          [Changeset.t()],
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) ::
          {:ok, [Connection.t()]}
          | {:error,
             {:connection_not_found, Connection.id()}
             | {:connection_scope_mismatch, Connection.id()}
             | {:connection_disabled, Connection.id()}}
  defp lock_connections(
         binding_changesets,
         organization_id,
         environment_id
       ) do
    connection_ids =
      Enum.map(
        binding_changesets,
        &Changeset.fetch_field!(&1, :connection_id)
      )

    Connections.lock_active(
      connection_ids,
      organization_id,
      environment_id
    )
  end

  @spec validate_connector_compatibility(
          PackageVersion.t(),
          [Changeset.t()],
          [Connection.t()]
        ) :: :ok | {:error, {:connector_mismatch, String.t()}}
  defp validate_connector_compatibility(
         package_version,
         binding_changesets,
         connections
       ) do
    endpoints_by_ref = Map.new(package_version.endpoints, &{&1.ref, &1})
    connections_by_id = Map.new(connections, &{&1.id, &1})

    binding_changesets
    |> Enum.sort_by(&Changeset.fetch_field!(&1, :ref))
    |> Enum.find_value(:ok, fn changeset ->
      ref = Changeset.fetch_field!(changeset, :ref)
      connection_id = Changeset.fetch_field!(changeset, :connection_id)
      endpoint = Map.fetch!(endpoints_by_ref, ref)
      connection = Map.fetch!(connections_by_id, connection_id)

      if endpoint_connector_id(endpoint) == connection.connector_id do
        false
      else
        {:error, {:connector_mismatch, ref}}
      end
    end)
  end

  @spec endpoint_connector_id(PackageVersionEndpoint.t()) :: Ecto.UUID.t()
  defp endpoint_connector_id(endpoint) do
    endpoint.operation.connector_version.connector_id
  end

  @spec fetch_deployment(EnvironmentDeployment.id()) ::
          {:ok, EnvironmentDeployment.t()} | {:error, :not_found}
  defp fetch_deployment(id) do
    case Repo.get(EnvironmentDeployment, id) do
      %EnvironmentDeployment{} = deployment -> {:ok, deployment}
      nil -> {:error, :not_found}
    end
  end

  @spec lock_deployment(EnvironmentDeployment.id()) ::
          {:ok, EnvironmentDeployment.t()} | {:error, :not_found}
  defp lock_deployment(id) do
    deployment =
      EnvironmentDeployment
      |> where([deployment], deployment.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case deployment do
      %EnvironmentDeployment{} = deployment -> {:ok, deployment}
      nil -> {:error, :not_found}
    end
  end

  @spec validate_replacement(EnvironmentDeployment.t(), map()) ::
          {:ok, Changeset.t()} | {:error, Changeset.t()}
  defp validate_replacement(deployment, attrs) do
    changeset =
      deployment
      |> EnvironmentDeployment.replace_changeset(attrs)
      |> require_attribute(attrs, :package_version_id)

    if changeset.valid? do
      {:ok, changeset}
    else
      {:error, changeset}
    end
  end

  @spec insert_deployment_or_rollback(Changeset.t()) ::
          EnvironmentDeployment.t() | no_return()
  defp insert_deployment_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, deployment} -> deployment
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @spec update_deployment_or_rollback(Changeset.t()) ::
          EnvironmentDeployment.t() | no_return()
  defp update_deployment_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, deployment} -> deployment
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @spec insert_bindings_or_rollback([Changeset.t()]) ::
          [EnvironmentDeploymentBinding.t()] | no_return()
  defp insert_bindings_or_rollback(changesets) do
    Enum.map(changesets, fn changeset ->
      case Repo.insert(changeset) do
        {:ok, binding} -> binding
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec delete_bindings(EnvironmentDeployment.id()) :: :ok
  defp delete_bindings(deployment_id) do
    EnvironmentDeploymentBinding
    |> where(
      [binding],
      binding.environment_deployment_id == ^deployment_id
    )
    |> Repo.delete_all()

    :ok
  end

  @spec load_bindings(EnvironmentDeployment.t()) :: EnvironmentDeployment.t()
  defp load_bindings(deployment) do
    bindings =
      EnvironmentDeploymentBinding
      |> where(
        [binding],
        binding.environment_deployment_id == ^deployment.id
      )
      |> order_by([binding], asc: binding.ref)
      |> Repo.all()

    attach_bindings(deployment, bindings)
  end

  @spec attach_bindings(
          EnvironmentDeployment.t(),
          [EnvironmentDeploymentBinding.t()]
        ) :: EnvironmentDeployment.t()
  defp attach_bindings(deployment, bindings) do
    %{deployment | bindings: Enum.sort_by(bindings, & &1.ref)}
  end

  @spec put_config_defaults(map()) :: map()
  defp put_config_defaults(attrs) do
    attrs
    |> put_attribute_default(:promotable_config, %{})
    |> put_attribute_default(:local_config, %{})
  end

  @spec put_attribute_default(map(), atom(), term()) :: map()
  defp put_attribute_default(attrs, key, default) do
    string_key = Atom.to_string(key)

    if Map.has_key?(attrs, key) or Map.has_key?(attrs, string_key) do
      attrs
    else
      put_default_with_matching_key_type(attrs, key, string_key, default)
    end
  end

  @spec put_default_with_matching_key_type(
          map(),
          atom(),
          String.t(),
          term()
        ) :: map()
  defp put_default_with_matching_key_type(attrs, key, string_key, default) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, string_key, default)
    else
      Map.put(attrs, key, default)
    end
  end

  @spec require_attribute(Changeset.t(), map(), atom()) :: Changeset.t()
  defp require_attribute(changeset, attrs, key) do
    string_key = Atom.to_string(key)

    if Map.has_key?(attrs, key) or Map.has_key?(attrs, string_key) do
      changeset
    else
      Changeset.add_error(
        changeset,
        key,
        "is required",
        validation: :required
      )
    end
  end

  @spec attribute(map(), atom(), term()) :: term()
  defp attribute(attrs, key, default \\ nil) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key), default)
    end
  end
end
