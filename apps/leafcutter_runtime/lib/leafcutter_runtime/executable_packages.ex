defmodule LeafcutterRuntime.ExecutablePackages do
  @moduledoc """
  Resolves immutable Catalog PackageVersions to compiled package Operations.

  Resolution joins the public Catalog projection with the checked-in build
  inventory by exact manifest digest. Catalog identifiers remain authoritative;
  package code contributes only literal modules that were compiled into the
  current release.
  """

  alias Leafcutter.Catalog.{
    Operation,
    Package,
    Packages,
    PackageVersion,
    PackageVersionEndpoint
  }
  alias LeafcutterConnectors.Package, as: PackageBehaviour
  alias LeafcutterConnectors.Package.Manifest
  alias LeafcutterRuntime.ExecutablePackages.{Binding, Inventory}

  @manifest_sha256_bytes 64
  @package_callbacks [
    manifest: 0,
    manifest_sha256: 0,
    source: 0,
    destinations: 0,
    resolve: 2
  ]
  @unlisted_ref_prefix "__leafcutter_unlisted_runtime_ref__"

  @typedoc "An allowlisted reason why a PackageVersion cannot resolve to compiled code."
  @type resolve_error ::
          :package_version_not_found
          | :package_not_bound
          | :package_not_installed
          | :manifest_mismatch
          | :invalid_binding

  @typedoc "A resolution error after the PackageVersion projection is already loaded."
  @type projection_error ::
          :package_not_bound
          | :package_not_installed
          | :manifest_mismatch
          | :invalid_binding

  @typep compiled_binding :: %{
           required(:manifest) => Manifest.t(),
           required(:source) => PackageBehaviour.endpoint_binding(),
           required(:destinations) => nonempty_list(PackageBehaviour.endpoint_binding())
         }

  @doc """
  Resolves one PackageVersion identifier to its compiled Operation binding.

  The lookup reads the immutable projection through `Catalog.Packages`, selects
  an installed package by exact manifest digest, verifies manifest topology,
  and combines literal modules with authoritative Operation and ContractVersion
  identifiers. No module name is read from persisted or external data.
  """
  @spec resolve(PackageVersion.id()) ::
          {:ok, Binding.t()} | {:error, resolve_error()}
  def resolve(package_version_id) do
    case Packages.get_version(package_version_id) do
      {:ok, package_version} ->
        resolve_projection(package_version)

      {:error, :not_found} ->
        {:error, :package_version_not_found}
    end
  end

  @doc false
  @spec resolve_projection(PackageVersion.t()) ::
          {:ok, Binding.t()} | {:error, projection_error()}
  def resolve_projection(%PackageVersion{} = package_version) do
    resolve_projection(package_version, Inventory.runtime_entries())
  end

  @doc false
  @spec resolve_projection(PackageVersion.t(), [Inventory.entry()]) ::
          {:ok, Binding.t()} | {:error, projection_error()}
  def resolve_projection(%PackageVersion{} = package_version, inventory_entries)
      when is_list(inventory_entries) do
    with {:ok, manifest_sha256} <- package_manifest_sha256(package_version),
         {:ok, inventory_entry} <-
           fetch_inventory_entry(inventory_entries, manifest_sha256),
         {:ok, compiled_binding} <-
           validate_compiled_binding(inventory_entry, manifest_sha256),
         {:ok, source, destinations} <-
           validate_projection(package_version, compiled_binding.manifest) do
      {:ok,
       build_binding(
         package_version,
         manifest_sha256,
         source,
         destinations,
         compiled_binding
       )}
    end
  end

  @spec package_manifest_sha256(PackageVersion.t()) ::
          {:ok, String.t()} | {:error, :package_not_bound}
  defp package_manifest_sha256(%PackageVersion{manifest_sha256: manifest_sha256}) do
    if valid_manifest_sha256?(manifest_sha256) do
      {:ok, manifest_sha256}
    else
      {:error, :package_not_bound}
    end
  end

  @spec fetch_inventory_entry([Inventory.entry()], String.t()) ::
          {:ok, Inventory.entry()} | {:error, :package_not_installed}
  defp fetch_inventory_entry(entries, manifest_sha256) do
    case Enum.find(entries, fn
           %{manifest_sha256: ^manifest_sha256} -> true
           _other_entry -> false
         end) do
      nil -> {:error, :package_not_installed}
      entry -> {:ok, entry}
    end
  end

  @spec validate_compiled_binding(Inventory.entry(), String.t()) ::
          {:ok, compiled_binding()} | {:error, :invalid_binding}
  defp validate_compiled_binding(
         %{binding: binding, manifest_sha256: manifest_sha256},
         manifest_sha256
       )
       when is_atom(binding) do
    if valid_package_module?(binding) do
      manifest = apply(binding, :manifest, [])
      binding_manifest_sha256 = apply(binding, :manifest_sha256, [])
      source = apply(binding, :source, [])
      destinations = apply(binding, :destinations, [])

      validate_compiled_values(
        binding,
        manifest,
        binding_manifest_sha256,
        manifest_sha256,
        source,
        destinations
      )
    else
      {:error, :invalid_binding}
    end
  end

  defp validate_compiled_binding(_entry, _manifest_sha256),
    do: {:error, :invalid_binding}

  @spec validate_compiled_values(
          module(),
          term(),
          term(),
          String.t(),
          term(),
          term()
        ) :: {:ok, compiled_binding()} | {:error, :invalid_binding}
  defp validate_compiled_values(
         binding,
         manifest,
         binding_manifest_sha256,
         manifest_sha256,
         source,
         destinations
       ) do
    with true <- valid_manifest?(manifest),
         true <- binding_manifest_sha256 == manifest_sha256,
         true <- valid_endpoint_binding?(source),
         true <- is_list(destinations) and destinations != [],
         true <- Enum.all?(destinations, &valid_endpoint_binding?/1),
         true <- binding_matches_manifest?(manifest, source, destinations),
         true <- operation_modules_valid?(source, destinations),
         true <- resolver_valid?(binding, source, destinations) do
      {:ok, %{manifest: manifest, source: source, destinations: destinations}}
    else
      _invalid -> {:error, :invalid_binding}
    end
  end

  @spec validate_projection(PackageVersion.t(), Manifest.t()) ::
          {:ok, PackageVersionEndpoint.t(), nonempty_list(PackageVersionEndpoint.t())}
          | {:error, :manifest_mismatch}
  defp validate_projection(package_version, manifest) do
    with {:ok, source, destinations} <- projection_endpoints(package_version.endpoints),
         true <- projection_matches_manifest?(package_version, manifest, source, destinations) do
      {:ok, source, destinations}
    else
      _mismatch -> {:error, :manifest_mismatch}
    end
  end

  @spec projection_endpoints(term()) ::
          {:ok, PackageVersionEndpoint.t(), nonempty_list(PackageVersionEndpoint.t())}
          | :error
  defp projection_endpoints(endpoints) when is_list(endpoints) do
    sources = Enum.filter(endpoints, &match?(%PackageVersionEndpoint{role: :source}, &1))

    destinations =
      endpoints
      |> Enum.filter(&match?(%PackageVersionEndpoint{role: :destination}, &1))
      |> Enum.sort_by(& &1.position)

    with [source] <- sources,
         true <- destinations != [],
         true <- length(endpoints) == length(destinations) + 1,
         true <- valid_projection_endpoint?(source, :source),
         true <- Enum.all?(destinations, &valid_projection_endpoint?(&1, :destination)),
         true <- destination_positions_valid?(destinations) do
      {:ok, source, destinations}
    else
      _invalid -> :error
    end
  end

  defp projection_endpoints(_endpoints), do: :error

  @spec projection_matches_manifest?(
          PackageVersion.t(),
          Manifest.t(),
          PackageVersionEndpoint.t(),
          [PackageVersionEndpoint.t()]
        ) :: boolean()
  defp projection_matches_manifest?(
         %PackageVersion{package: %Package{name: package_name}, version: package_version},
         %Manifest{} = manifest,
         source,
         destinations
       ) do
    package_name == manifest.package_name and
      package_version == manifest.package_version and
      source.ref == manifest.source_ref and
      Enum.map(destinations, & &1.ref) == manifest.destination_refs
  end

  defp projection_matches_manifest?(
         _package_version,
         _manifest,
         _source,
         _destinations
       ),
       do: false

  @spec valid_projection_endpoint?(PackageVersionEndpoint.t(), :source | :destination) ::
          boolean()
  defp valid_projection_endpoint?(
         %PackageVersionEndpoint{
           ref: ref,
           role: endpoint_role,
           position: position,
           operation_id: operation_id,
           operation: %Operation{id: loaded_operation_id, role: operation_role},
           contract_version_id: contract_version_id
         },
         expected_role
       ) do
    endpoint_role == expected_role and
      operation_role == expected_role and
      loaded_operation_id == operation_id and
      valid_endpoint_position?(expected_role, position) and
      valid_ref?(ref) and
      is_binary(operation_id) and
      is_binary(contract_version_id)
  end

  defp valid_projection_endpoint?(_endpoint, _role), do: false

  @spec valid_endpoint_position?(:source | :destination, term()) :: boolean()
  defp valid_endpoint_position?(:source, nil), do: true

  defp valid_endpoint_position?(:destination, position)
       when is_integer(position) and position >= 0,
       do: true

  defp valid_endpoint_position?(_role, _position), do: false

  @spec destination_positions_valid?([PackageVersionEndpoint.t()]) :: boolean()
  defp destination_positions_valid?(destinations) do
    destinations
    |> Enum.with_index()
    |> Enum.all?(fn {%PackageVersionEndpoint{position: position}, index} ->
      position == index
    end)
  end

  @spec build_binding(
          PackageVersion.t(),
          String.t(),
          PackageVersionEndpoint.t(),
          nonempty_list(PackageVersionEndpoint.t()),
          compiled_binding()
        ) :: Binding.t()
  defp build_binding(
         package_version,
         manifest_sha256,
         source,
         destinations,
         compiled_binding
       ) do
    {_source_ref, source_module} = compiled_binding.source

    destination_bindings =
      Enum.zip_with(destinations, compiled_binding.destinations, fn
        endpoint, {_ref, module} -> resolved_endpoint(endpoint, module)
      end)

    %Binding{
      package_version_id: package_version.id,
      manifest_sha256: manifest_sha256,
      source: resolved_endpoint(source, source_module),
      destinations: destination_bindings
    }
  end

  @spec resolved_endpoint(PackageVersionEndpoint.t(), module()) ::
          Binding.endpoint()
  defp resolved_endpoint(endpoint, module) do
    %{
      ref: endpoint.ref,
      operation_id: endpoint.operation_id,
      contract_version_id: endpoint.contract_version_id,
      module: module
    }
  end

  @spec valid_package_module?(module()) :: boolean()
  defp valid_package_module?(module) do
    PackageBehaviour in module_behaviours(module) and
      Enum.all?(@package_callbacks, fn {function, arity} ->
        function_exported?(module, function, arity)
      end)
  end

  @spec valid_manifest?(term()) :: boolean()
  defp valid_manifest?(
         %Manifest{
           manifest_version: 1,
           package_name: package_name,
           package_version: package_version,
           source_ref: source_ref,
           destination_refs: destination_refs
         }
       ) do
    valid_ref?(package_name) and valid_ref?(package_version) and valid_ref?(source_ref) and
      is_list(destination_refs) and destination_refs != [] and
      Enum.all?(destination_refs, &valid_ref?/1) and
      length(Enum.uniq([source_ref | destination_refs])) == length(destination_refs) + 1
  end

  defp valid_manifest?(_manifest), do: false

  @spec binding_matches_manifest?(
          Manifest.t(),
          PackageBehaviour.endpoint_binding(),
          [PackageBehaviour.endpoint_binding()]
        ) :: boolean()
  defp binding_matches_manifest?(manifest, {source_ref, _module}, destinations) do
    source_ref == manifest.source_ref and
      Enum.map(destinations, &elem(&1, 0)) == manifest.destination_refs
  end

  @spec operation_modules_valid?(
          PackageBehaviour.endpoint_binding(),
          [PackageBehaviour.endpoint_binding()]
        ) :: boolean()
  defp operation_modules_valid?({_source_ref, source_module}, destinations) do
    destination_modules = Enum.map(destinations, &elem(&1, 1))
    modules = [source_module | destination_modules]

    length(Enum.uniq(modules)) == length(modules) and
      valid_operation_module?(
        source_module,
        LeafcutterConnectors.Operation.Read,
        :read
      ) and
      Enum.all?(destination_modules, fn module ->
        valid_operation_module?(
          module,
          LeafcutterConnectors.Operation.Write,
          :write
        )
      end)
  end

  @spec valid_operation_module?(module(), module(), atom()) :: boolean()
  defp valid_operation_module?(module, behaviour, callback) do
    behaviour in module_behaviours(module) and function_exported?(module, callback, 1)
  end

  @spec resolver_valid?(
          module(),
          PackageBehaviour.endpoint_binding(),
          [PackageBehaviour.endpoint_binding()]
        ) :: boolean()
  defp resolver_valid?(binding, {source_ref, source_module}, destinations) do
    destination_resolutions_valid? =
      Enum.all?(destinations, fn {ref, module} ->
        apply(binding, :resolve, [ref, :destination]) == {:ok, module} and
          apply(binding, :resolve, [ref, :source]) == {:error, :not_found}
      end)

    unlisted_ref = unlisted_ref([source_ref | Enum.map(destinations, &elem(&1, 0))])

    apply(binding, :resolve, [source_ref, :source]) == {:ok, source_module} and
      apply(binding, :resolve, [source_ref, :destination]) == {:error, :not_found} and
      destination_resolutions_valid? and
      apply(binding, :resolve, [unlisted_ref, :source]) == {:error, :not_found} and
      apply(binding, :resolve, [unlisted_ref, :destination]) == {:error, :not_found}
  end

  @spec unlisted_ref([String.t()]) :: String.t()
  defp unlisted_ref(refs) do
    find_unlisted_ref(MapSet.new(refs), 0)
  end

  @spec find_unlisted_ref(MapSet.t(String.t()), non_neg_integer()) :: String.t()
  defp find_unlisted_ref(refs, index) do
    candidate = @unlisted_ref_prefix <> Integer.to_string(index)

    if MapSet.member?(refs, candidate) do
      find_unlisted_ref(refs, index + 1)
    else
      candidate
    end
  end

  @spec valid_endpoint_binding?(term()) :: boolean()
  defp valid_endpoint_binding?({ref, module}) do
    valid_ref?(ref) and valid_module?(module)
  end

  defp valid_endpoint_binding?(_binding), do: false

  @spec valid_ref?(term()) :: boolean()
  defp valid_ref?(ref) when is_binary(ref) do
    String.valid?(ref) and String.trim(ref) != "" and String.length(ref) <= 255
  end

  defp valid_ref?(_ref), do: false

  @spec valid_module?(term()) :: boolean()
  defp valid_module?(module) when is_atom(module) and module not in [nil, true, false] do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  defp valid_module?(_module), do: false

  @spec valid_manifest_sha256?(term()) :: boolean()
  defp valid_manifest_sha256?(manifest_sha256)
       when is_binary(manifest_sha256) and
              byte_size(manifest_sha256) == @manifest_sha256_bytes do
    manifest_sha256
    |> :binary.bin_to_list()
    |> Enum.all?(fn byte -> byte in ?0..?9 or byte in ?a..?f end)
  end

  defp valid_manifest_sha256?(_manifest_sha256), do: false

  @spec module_behaviours(module()) :: [module()]
  defp module_behaviours(module) do
    module
    |> apply(:module_info, [:attributes])
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.uniq()
  end
end
