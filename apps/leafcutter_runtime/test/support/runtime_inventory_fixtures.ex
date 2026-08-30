defmodule LeafcutterRuntime.RuntimeInventoryFixtures do
  @moduledoc false

  alias LeafcutterRuntime.ExecutablePackages.Inventory

  @type restore :: (-> :ok)

  @spec replace_binding(module()) :: restore()
  def replace_binding(binding) when is_atom(binding) do
    inventory = Inventory
    {:module, ^inventory} = Code.ensure_loaded(inventory)
    {^inventory, original_binary, original_filename} = :code.get_object_code(inventory)

    production_entries = Inventory.entries()

    runtime_entries =
      Enum.map(Inventory.runtime_entries(), &Map.replace!(&1, :binding, binding))

    load_inventory!(inventory, production_entries, runtime_entries)

    fn ->
      unload_inventory(inventory)
      {:module, ^inventory} = :code.load_binary(inventory, original_filename, original_binary)
      :ok
    end
  end

  defp load_inventory!(inventory, production_entries, runtime_entries) do
    unload_inventory(inventory)

    quoted =
      quote do
        defmodule unquote(inventory) do
          @moduledoc false

          @spec entries() :: [map()]
          def entries, do: unquote(Macro.escape(production_entries))

          @spec runtime_entries() :: [map()]
          def runtime_entries, do: unquote(Macro.escape(runtime_entries))
        end
      end

    previous_options = Code.compiler_options(ignore_module_conflict: true)

    try do
      [{^inventory, _binary}] = Code.compile_quoted(quoted)
    after
      Code.compiler_options(Map.to_list(previous_options))
    end

    :ok
  end

  defp unload_inventory(inventory) do
    _purged? = :code.purge(inventory)
    _deleted? = :code.delete(inventory)
    :ok
  end
end
