defmodule LeafcutterRuntime.PackageBuild do
  @moduledoc false

  @required_keys Enum.sort([:app, :path, :binding, :manifest_sha256])
  @digest_regex ~r/\A[0-9a-f]{64}\z/
  @app_regex ~r/\A[a-z][a-z0-9_]*\z/
  @max_symlink_hops 40

  @type entry :: %{
          app: atom(),
          path: String.t(),
          binding: module(),
          manifest_sha256: String.t()
        }

  @doc false
  @spec load!(Path.t(), Path.t()) :: [entry()]
  def load!(inventory_file, repository_root) do
    inventory_file
    |> File.read!()
    |> parse!(inventory_file)
    |> validate_entries!(repository_root)
  end

  @doc false
  @spec parse!(binary(), Path.t()) :: [entry()]
  def parse!(source, inventory_file) when is_binary(source) do
    ast =
      case Code.string_to_quoted(source,
             file: inventory_file,
             columns: true
           ) do
        {:ok, ast} -> ast
        {:error, _reason} -> invalid!("build.exs must contain one literal list")
      end

    parse_entries!(ast)
  end

  @doc false
  @spec validate_entries!([entry()], Path.t()) :: [entry()]
  def validate_entries!(entries, repository_root)
      when is_list(entries) and is_binary(repository_root) do
    packages_root = Path.join(repository_root, "packages")

    unless File.dir?(packages_root) do
      invalid!("packages directory does not exist")
    end

    entries =
      entries
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} ->
        validate_entry_shape!(entry, index)
      end)

    Enum.each([:app, :path, :binding, :manifest_sha256], fn field ->
      ensure_unique!(entries, field)
    end)

    packages_real_path = realpath!(packages_root)

    package_real_paths =
      Enum.map(entries, fn entry ->
        validate_package_path!(entry, repository_root, packages_root, packages_real_path)
      end)

    ensure_unique_values!(package_real_paths, :path)
    Enum.sort_by(entries, &Atom.to_string(&1.app))
  end

  def validate_entries!(_entries, _repository_root) do
    invalid!("build.exs must contain one literal list")
  end

  @doc false
  @spec dependency_specs([entry()], Path.t()) :: [{atom(), keyword()}]
  def dependency_specs(entries, repository_root) do
    Enum.map(entries, fn entry ->
      {entry.app, path: Path.expand(entry.path, repository_root)}
    end)
  end

  @doc false
  @spec validate_compiled!([entry()], Path.t()) :: [entry()]
  def validate_compiled!(entries, repository_root) do
    entries = validate_entries!(entries, repository_root)

    Enum.each(entries, fn entry ->
      validate_compiled_entry!(entry, repository_root)
    end)

    entries
  end

  @spec parse_entries!(term()) :: [entry()]
  defp parse_entries!(entries) when is_list(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} -> parse_entry!(entry, index) end)
  end

  defp parse_entries!(_ast) do
    invalid!("build.exs must contain one literal list")
  end

  @spec parse_entry!(term(), pos_integer()) :: entry()
  defp parse_entry!({:%{}, _metadata, pairs}, index) when is_list(pairs) do
    keys =
      Enum.map(pairs, fn
        {key, _value} when is_atom(key) -> key
        _pair -> invalid!("entry #{index} must use literal atom keys")
      end)

    if Enum.sort(keys) != @required_keys or length(Enum.uniq(keys)) != length(keys) do
      invalid!("entry #{index} must contain exactly the required keys")
    end

    Map.new(pairs, fn {key, value} ->
      {key, parse_value!(key, value, index)}
    end)
  end

  defp parse_entry!(_entry, index) do
    invalid!("entry #{index} must be a literal map")
  end

  @spec parse_value!(atom(), term(), pos_integer()) :: term()
  defp parse_value!(:app, app, _index) when is_atom(app), do: app
  defp parse_value!(:path, path, _index) when is_binary(path), do: path

  defp parse_value!(:manifest_sha256, digest, _index) when is_binary(digest),
    do: digest

  defp parse_value!(:binding, {:__aliases__, _metadata, parts} = binding, index)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      module = Macro.expand(binding, __ENV__)

      if valid_module?(module) do
        module
      else
        invalid!("entry #{index} binding must be a literal module")
      end
    else
      invalid!("entry #{index} binding must be a literal module")
    end
  end

  defp parse_value!(:binding, binding, index) when is_atom(binding) do
    if valid_module?(binding) do
      binding
    else
      invalid!("entry #{index} binding must be a literal module")
    end
  end

  defp parse_value!(field, _value, index) do
    invalid!("entry #{index} #{field} must be a literal value")
  end

  @spec validate_entry_shape!(term(), pos_integer()) :: entry()
  defp validate_entry_shape!(entry, index) when is_map(entry) do
    if Enum.sort(Map.keys(entry)) != @required_keys do
      invalid!("entry #{index} must contain exactly the required keys")
    end

    app = Map.fetch!(entry, :app)
    path = Map.fetch!(entry, :path)
    binding = Map.fetch!(entry, :binding)
    digest = Map.fetch!(entry, :manifest_sha256)

    unless valid_app?(app) do
      invalid!("entry #{index} app must be a literal Mix application atom")
    end

    unless valid_path_literal?(path) do
      invalid!("entry #{index} path must be a relative UTF-8 path without traversal")
    end

    unless valid_module?(binding) do
      invalid!("entry #{index} binding must be a literal module")
    end

    unless is_binary(digest) and Regex.match?(@digest_regex, digest) do
      invalid!("entry #{index} manifest_sha256 must be lowercase SHA-256 hex")
    end

    %{app: app, path: path, binding: binding, manifest_sha256: digest}
  end

  defp validate_entry_shape!(_entry, index) do
    invalid!("entry #{index} must be a literal map")
  end

  @spec validate_package_path!(entry(), Path.t(), Path.t(), Path.t()) :: Path.t()
  defp validate_package_path!(entry, repository_root, packages_root, packages_real_path) do
    package_path = Path.expand(entry.path, repository_root)

    unless contained_path?(package_path, packages_root) do
      invalid!("package path must remain inside packages")
    end

    unless File.dir?(package_path) do
      invalid!("package path does not exist")
    end

    package_real_path = realpath!(package_path)

    unless contained_path?(package_real_path, packages_real_path) do
      invalid!("package path realpath must remain inside packages")
    end

    mix_file = Path.join(package_path, "mix.exs")
    manifest_file = Path.join(package_path, "manifest.json")

    unless File.regular?(mix_file) do
      invalid!("package Mix project is missing")
    end

    unless File.regular?(manifest_file) do
      invalid!("package root manifest is missing")
    end

    expected_mix_real_path = Path.join(package_real_path, "mix.exs")
    expected_manifest_real_path = Path.join(package_real_path, "manifest.json")

    unless realpath!(mix_file) == expected_mix_real_path do
      invalid!("package Mix project must be a regular file inside the package")
    end

    unless realpath!(manifest_file) == expected_manifest_real_path do
      invalid!("package root manifest must be a regular file inside the package")
    end

    package_real_path
  end

  @spec validate_compiled_entry!(entry(), Path.t()) :: :ok
  defp validate_compiled_entry!(entry, repository_root) do
    package_path = Path.expand(entry.path, repository_root)
    manifest_path = Path.join(package_path, "manifest.json")
    manifest_bytes = File.read!(manifest_path)
    manifest = parse_manifest!(manifest_bytes)
    manifest_sha256 = sha256(manifest_bytes)

    unless manifest_sha256 == entry.manifest_sha256 do
      invalid!("root manifest digest does not match the inventory")
    end

    ensure_compiled!(entry.binding, "binding module is not compiled")
    ensure_application_owns_binding!(entry.app, entry.binding)
    ensure_root_manifest_resource!(entry.binding, manifest_path)
    validate_binding!(entry.binding, manifest, manifest_sha256)
  end

  @spec parse_manifest!(binary()) :: term()
  defp parse_manifest!(manifest_bytes) do
    manifest_module = LeafcutterConnectors.Package.Manifest

    case apply(manifest_module, :parse, [manifest_bytes]) do
      {:ok, manifest} -> manifest
      {:error, _reason} -> invalid!("package root manifest is invalid")
    end
  end

  @spec ensure_application_owns_binding!(atom(), module()) :: :ok
  defp ensure_application_owns_binding!(app, binding) do
    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, ^app}} -> :ok
      {:error, _reason} -> invalid!("inventory app is not a compiled Mix application")
    end

    modules = Application.spec(app, :modules)

    unless is_list(modules) and binding in modules do
      invalid!("binding module does not belong to the inventory app")
    end
  end

  @spec ensure_root_manifest_resource!(module(), Path.t()) :: :ok
  defp ensure_root_manifest_resource!(binding, manifest_path) do
    external_resources =
      binding
      |> module_attributes()
      |> Keyword.get_values(:external_resource)
      |> List.flatten()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&Path.expand/1)

    unless Path.expand(manifest_path) in external_resources do
      invalid!("binding was not compiled from the package root manifest")
    end
  end

  @spec validate_binding!(module(), term(), String.t()) :: :ok
  defp validate_binding!(binding, manifest, manifest_sha256) do
    package_behaviour = LeafcutterConnectors.Package

    unless package_behaviour in module_behaviours(binding) do
      invalid!("binding module does not implement the Package behaviour")
    end

    required_callbacks = [
      manifest: 0,
      manifest_sha256: 0,
      source: 0,
      destinations: 0,
      resolve: 2
    ]

    unless Enum.all?(required_callbacks, fn {name, arity} ->
             function_exported?(binding, name, arity)
           end) do
      invalid!("binding module does not export the Package callbacks")
    end

    binding_manifest = safe_apply!(binding, :manifest, [])
    binding_sha256 = safe_apply!(binding, :manifest_sha256, [])
    source = safe_apply!(binding, :source, [])
    destinations = safe_apply!(binding, :destinations, [])

    unless binding_manifest == manifest and binding_sha256 == manifest_sha256 do
      invalid!("compiled binding does not match the package root manifest")
    end

    validate_endpoint_bindings!(binding, manifest, source, destinations)
  end

  @spec validate_endpoint_bindings!(module(), term(), term(), term()) :: :ok
  defp validate_endpoint_bindings!(binding, manifest, source, destinations) do
    with %{source_ref: source_ref, destination_refs: destination_refs}
         when is_binary(source_ref) and is_list(destination_refs) <- manifest,
         {^source_ref, source_module} <- source,
         true <- valid_module?(source_module),
         true <- is_list(destinations) and destinations != [],
         true <- Enum.all?(destinations, &valid_endpoint_binding?/1),
         ^destination_refs <- Enum.map(destinations, &elem(&1, 0)) do
      modules = [source_module | Enum.map(destinations, &elem(&1, 1))]

      unless length(Enum.uniq(modules)) == length(modules) do
        invalid!("Operation modules must be unique across package bindings")
      end

      validate_operation!(source_module, LeafcutterConnectors.Operation.Read, :read)

      Enum.each(destinations, fn {_ref, module} ->
        validate_operation!(module, LeafcutterConnectors.Operation.Write, :write)
      end)

      validate_resolver!(binding, source, destinations)
    else
      _invalid -> invalid!("compiled binding topology does not match the root manifest")
    end
  end

  @spec validate_resolver!(module(), {String.t(), module()}, [{String.t(), module()}]) :: :ok
  defp validate_resolver!(binding, {source_ref, source_module}, destinations) do
    unless safe_apply!(binding, :resolve, [source_ref, :source]) == {:ok, source_module} do
      invalid!("compiled binding source resolution is invalid")
    end

    Enum.each(destinations, fn {ref, module} ->
      unless safe_apply!(binding, :resolve, [ref, :destination]) == {:ok, module} do
        invalid!("compiled binding destination resolution is invalid")
      end
    end)

    sentinel_ref = "__leafcutter_unlisted_inventory_ref__"

    unless safe_apply!(binding, :resolve, [sentinel_ref, :source]) == {:error, :not_found} and
             safe_apply!(binding, :resolve, [sentinel_ref, :destination]) ==
               {:error, :not_found} do
      invalid!("compiled binding resolves an undeclared ref")
    end

    :ok
  end

  @spec validate_operation!(module(), module(), atom()) :: :ok
  defp validate_operation!(module, behaviour, callback) do
    ensure_compiled!(module, "Operation module is not compiled")

    unless behaviour in module_behaviours(module) and
             function_exported?(module, callback, 1) do
      invalid!("Operation module does not implement its declared role")
    end
  end

  @spec safe_apply!(module(), atom(), [term()]) :: term()
  defp safe_apply!(module, function, arguments) do
    apply(module, function, arguments)
  rescue
    _exception -> invalid!("compiled binding callback failed")
  catch
    _kind, _reason -> invalid!("compiled binding callback failed")
  end

  @spec ensure_compiled!(module(), String.t()) :: :ok
  defp ensure_compiled!(module, error_message) do
    case Code.ensure_compiled(module) do
      {:module, ^module} -> :ok
      {:error, _reason} -> invalid!(error_message)
    end
  end

  @spec module_behaviours(module()) :: [module()]
  defp module_behaviours(module) do
    module
    |> module_attributes()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.uniq()
  end

  @spec module_attributes(module()) :: keyword()
  defp module_attributes(module) do
    apply(module, :module_info, [:attributes])
  end

  @spec valid_endpoint_binding?(term()) :: boolean()
  defp valid_endpoint_binding?({ref, module}) do
    is_binary(ref) and String.valid?(ref) and valid_module?(module)
  end

  defp valid_endpoint_binding?(_binding), do: false

  @spec valid_app?(term()) :: boolean()
  defp valid_app?(app) when is_atom(app) and app not in [nil, true, false] do
    Regex.match?(@app_regex, Atom.to_string(app))
  end

  defp valid_app?(_app), do: false

  @spec valid_module?(term()) :: boolean()
  defp valid_module?(module) when is_atom(module) and module not in [nil, true, false] do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  defp valid_module?(_module), do: false

  @spec valid_path_literal?(term()) :: boolean()
  defp valid_path_literal?(path) when is_binary(path) do
    components = String.split(path, ~r{[\\/]}, trim: false)

    String.valid?(path) and path != "" and not String.contains?(path, <<0>>) and
      Path.type(path) == :relative and
      not Regex.match?(~r/\A[A-Za-z]:[\\\/]/, path) and
      Enum.all?(components, &(&1 not in ["", ".", ".."]))
  end

  defp valid_path_literal?(_path), do: false

  @spec ensure_unique!([entry()], atom()) :: :ok
  defp ensure_unique!(entries, field) do
    entries
    |> Enum.map(&Map.fetch!(&1, field))
    |> ensure_unique_values!(field)
  end

  @spec ensure_unique_values!([term()], atom()) :: :ok
  defp ensure_unique_values!(values, field) do
    if length(Enum.uniq(values)) == length(values) do
      :ok
    else
      invalid!("duplicate #{field}")
    end
  end

  @spec contained_path?(Path.t(), Path.t()) :: boolean()
  defp contained_path?(path, root) do
    relative = Path.relative_to(path, root)

    Path.type(relative) == :relative and
      Enum.all?(Path.split(relative), &(&1 != ".."))
  end

  @spec realpath!(Path.t()) :: Path.t()
  defp realpath!(path) do
    resolve_realpath!(Path.expand(path), 0)
  end

  @spec resolve_realpath!(Path.t(), non_neg_integer()) :: Path.t()
  defp resolve_realpath!(_path, hops) when hops > @max_symlink_hops do
    invalid!("package path contains too many symbolic links")
  end

  defp resolve_realpath!(path, hops) do
    case Path.split(path) do
      [root | components] -> resolve_components!(root, components, hops)
      [] -> invalid!("package path does not exist")
    end
  end

  @spec resolve_components!(Path.t(), [String.t()], non_neg_integer()) :: Path.t()
  defp resolve_components!(resolved, [], _hops), do: resolved

  defp resolve_components!(resolved, [component | remaining], hops) do
    candidate = Path.join(resolved, component)

    case File.lstat(candidate) do
      {:ok, %File.Stat{type: :symlink}} ->
        target =
          case File.read_link(candidate) do
            {:ok, target} -> target
            {:error, _reason} -> invalid!("package symbolic link cannot be resolved")
          end

        unless String.valid?(target) do
          invalid!("package symbolic link target is not UTF-8")
        end

        target =
          case Path.type(target) do
            :absolute -> target
            _relative -> Path.expand(target, Path.dirname(candidate))
          end

        unresolved = Enum.reduce(remaining, target, &Path.join(&2, &1))
        resolve_realpath!(unresolved, hops + 1)

      {:ok, _stat} ->
        resolve_components!(candidate, remaining, hops)

      {:error, _reason} ->
        invalid!("package path does not exist")
    end
  end

  @spec sha256(binary()) :: String.t()
  defp sha256(bytes) do
    bytes
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec invalid!(String.t()) :: no_return()
  defp invalid!(reason) do
    raise ArgumentError, "invalid package inventory: #{reason}"
  end
end
