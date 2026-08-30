defmodule LeafcutterConnectors.Package do
  @moduledoc """
  Compiled binding contract between one Package Manifest and Operation modules.

  `use LeafcutterConnectors.Package` validates the manifest and literal endpoint
  bindings during compilation. The generated callbacks contain only validated
  values and compiled module atoms; they never read the filesystem at runtime.
  """

  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Package.Manifest

  @required_options [:manifest, :source, :destinations]

  @typedoc "A literal endpoint ref and its compiled Operation module."
  @type endpoint_binding :: {String.t(), module()}

  @doc "Returns the validated Package Manifest v1 projection."
  @callback manifest() :: Manifest.t()

  @doc "Returns the lowercase SHA-256 digest of the exact manifest bytes."
  @callback manifest_sha256() :: String.t()

  @doc "Returns the single source ref and compiled Read Operation module."
  @callback source() :: endpoint_binding()

  @doc "Returns ordered destination refs and compiled Write Operation modules."
  @callback destinations() :: nonempty_list(endpoint_binding())

  @doc "Resolves a declared endpoint ref and role to its compiled module."
  @callback resolve(String.t(), :source | :destination) ::
              {:ok, module()} | {:error, :not_found}

  @doc """
  Defines a compiled package binding from one manifest and literal modules.

  The `:manifest` expression must evaluate to an absolute path during
  compilation. `:source` and every `:destinations` entry must be literal
  `{ref, Module}` tuples. Unknown, missing, or repeated options are rejected.
  """
  defmacro __using__(options) do
    caller = __CALLER__
    validate_options!(options, caller)

    manifest_path = Keyword.fetch!(options, :manifest)
    source = options |> Keyword.fetch!(:source) |> expand_binding!(:source, caller)

    destinations =
      options
      |> Keyword.fetch!(:destinations)
      |> expand_destinations!(caller)

    quote do
      @behaviour LeafcutterConnectors.Package

      @leafcutter_package_manifest_path unquote(manifest_path)

      @leafcutter_package_compiled_binding LeafcutterConnectors.Package.__compile_binding__!(
                                            @leafcutter_package_manifest_path,
                                            unquote(Macro.escape(source)),
                                            unquote(Macro.escape(destinations)),
                                            __ENV__
                                          )
      @external_resource @leafcutter_package_manifest_path

      @leafcutter_package_manifest elem(@leafcutter_package_compiled_binding, 0)
      @leafcutter_package_manifest_sha256 elem(
                                           @leafcutter_package_compiled_binding,
                                           1
                                         )
      @leafcutter_package_source unquote(Macro.escape(source))
      @leafcutter_package_destinations unquote(Macro.escape(destinations))

      @impl true
      def manifest, do: @leafcutter_package_manifest

      @impl true
      def manifest_sha256, do: @leafcutter_package_manifest_sha256

      @impl true
      def source, do: @leafcutter_package_source

      @impl true
      def destinations, do: @leafcutter_package_destinations

      @impl true
      def resolve(ref, :source) do
        case @leafcutter_package_source do
          {^ref, module} -> {:ok, module}
          {_source_ref, _module} -> {:error, :not_found}
        end
      end

      def resolve(ref, :destination) do
        case List.keyfind(@leafcutter_package_destinations, ref, 0) do
          {_destination_ref, module} -> {:ok, module}
          nil -> {:error, :not_found}
        end
      end

      def resolve(_ref, _role), do: {:error, :not_found}
    end
  end

  @doc false
  @spec __compile_binding__!(
          term(),
          endpoint_binding(),
          [endpoint_binding()],
          Macro.Env.t()
        ) :: {Manifest.t(), String.t()}
  def __compile_binding__!(manifest_path, source, destinations, caller) do
    manifest_path = validate_manifest_path!(manifest_path, caller)

    bytes =
      case File.read(manifest_path) do
        {:ok, bytes} ->
          bytes

        {:error, reason} ->
          formatted_reason =
            reason
            |> :file.format_error()
            |> IO.iodata_to_binary()

          compile_error!(
            caller,
            "could not read package manifest: #{formatted_reason}"
          )
      end

    manifest =
      case Manifest.parse(bytes) do
        {:ok, manifest} ->
          manifest

        {:error, error} ->
          compile_error!(caller, "invalid package manifest: #{inspect(error)}")
      end

    __validate_bindings__!(manifest, source, destinations, caller)

    {manifest, Manifest.sha256(bytes)}
  end

  @doc false
  @spec __validate_bindings__!(
          term(),
          term(),
          term(),
          Macro.Env.t()
        ) :: :ok
  def __validate_bindings__!(%Manifest{} = manifest, source, destinations, caller) do
    if valid_endpoint_binding?(source) and is_list(destinations) and
         Enum.all?(destinations, &valid_endpoint_binding?/1) do
      validate_bindings!(manifest, source, destinations, caller)
    else
      compile_error!(caller, "package bindings have an invalid shape")
    end
  end

  def __validate_bindings__!(_manifest, _source, _destinations, caller) do
    compile_error!(caller, "package bindings have an invalid shape")
  end

  @spec validate_bindings!(
          Manifest.t(),
          endpoint_binding(),
          [endpoint_binding()],
          Macro.Env.t()
        ) :: :ok
  defp validate_bindings!(
         %Manifest{} = manifest,
         {source_ref, source_module} = source,
         destinations,
         caller
       ) do
    destination_refs = Enum.map(destinations, &elem(&1, 0))

    if source_ref != manifest.source_ref do
      compile_error!(caller, "source binding does not match the manifest")
    end

    if destination_refs != manifest.destination_refs do
      compile_error!(
        caller,
        "destination bindings do not exactly match manifest refs and order"
      )
    end

    bindings = [source | destinations]
    modules = Enum.map(bindings, &elem(&1, 1))

    if map_size(Map.new(modules, &{&1, true})) != length(modules) do
      compile_error!(caller, "Operation modules must be unique across bindings")
    end

    validate_operation_module!(source_module, Operation.Read, :read, caller)

    Enum.each(destinations, fn {_ref, module} ->
      validate_operation_module!(module, Operation.Write, :write, caller)
    end)

    :ok
  end

  @spec validate_options!(term(), Macro.Env.t()) :: :ok
  defp validate_options!(options, caller) do
    valid_options? =
      is_list(options) and Keyword.keyword?(options) and
        length(options) == length(@required_options) and
        Enum.sort(Keyword.keys(options)) == Enum.sort(@required_options)

    if valid_options? do
      :ok
    else
      compile_error!(
        caller,
        "expected exactly :manifest, :source, and :destinations options"
      )
    end
  end

  @spec expand_destinations!(term(), Macro.Env.t()) ::
          nonempty_list(endpoint_binding())
  defp expand_destinations!([], caller) do
    compile_error!(caller, "destinations must be a non-empty literal list")
  end

  defp expand_destinations!(destinations, caller) when is_list(destinations) do
    Enum.map(destinations, &expand_binding!(&1, :destination, caller))
  end

  defp expand_destinations!(_destinations, caller) do
    compile_error!(caller, "destinations must be a non-empty literal list")
  end

  @spec expand_binding!(term(), :source | :destination, Macro.Env.t()) ::
          endpoint_binding()
  defp expand_binding!(binding, role, caller) do
    case binding_parts(binding) do
      {ref, module_ast} when is_binary(ref) ->
        module = Macro.expand(module_ast, caller)

        if valid_ref?(ref) and is_atom(module) and
             module not in [nil, true, false] do
          {ref, module}
        else
          invalid_binding_literal!(role, caller)
        end

      _invalid ->
        invalid_binding_literal!(role, caller)
    end
  end

  @spec binding_parts(term()) :: {term(), Macro.t()} | :error
  defp binding_parts({:{}, _metadata, [ref, module_ast]}),
    do: {ref, module_ast}

  defp binding_parts({ref, module_ast}), do: {ref, module_ast}
  defp binding_parts(_binding), do: :error

  @spec valid_ref?(term()) :: boolean()
  defp valid_ref?(ref) when is_binary(ref) do
    String.valid?(ref) and String.trim(ref) != "" and String.length(ref) <= 255
  end

  defp valid_ref?(_ref), do: false

  @spec valid_endpoint_binding?(term()) :: boolean()
  defp valid_endpoint_binding?({ref, module}) do
    valid_ref?(ref) and is_atom(module) and module not in [nil, true, false]
  end

  defp valid_endpoint_binding?(_binding), do: false

  @spec invalid_binding_literal!(:source | :destination, Macro.Env.t()) ::
          no_return()
  defp invalid_binding_literal!(role, caller) do
    compile_error!(
      caller,
      "#{role} bindings must use literal {ref, Module} tuples"
    )
  end

  @spec validate_manifest_path!(term(), Macro.Env.t()) :: String.t()
  defp validate_manifest_path!(path, caller)
       when is_binary(path) do
    if String.valid?(path) and Path.type(path) == :absolute do
      path
    else
      compile_error!(caller, "manifest must evaluate to an absolute UTF-8 path")
    end
  end

  defp validate_manifest_path!(_path, caller) do
    compile_error!(caller, "manifest must evaluate to an absolute UTF-8 path")
  end

  @spec validate_operation_module!(
          module(),
          module(),
          atom(),
          Macro.Env.t()
        ) :: :ok
  defp validate_operation_module!(module, behaviour, callback, caller) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        behaviours =
          module
          |> module_behaviours()
          |> Enum.uniq()

        if behaviour in behaviours and function_exported?(module, callback, 1) do
          :ok
        else
          compile_error!(
            caller,
            "#{inspect(module)} must implement #{inspect(behaviour)}"
          )
        end

      {:error, _reason} ->
        compile_error!(caller, "#{inspect(module)} is not compiled")
    end
  end

  @spec module_behaviours(module()) :: [module()]
  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  @spec compile_error!(Macro.Env.t(), String.t()) :: no_return()
  defp compile_error!(caller, description) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description: description
  end
end
