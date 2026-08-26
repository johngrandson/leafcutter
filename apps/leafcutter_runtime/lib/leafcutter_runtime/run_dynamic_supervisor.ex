defmodule LeafcutterRuntime.RunDynamicSupervisor do
  @moduledoc """
  Supervises per-Run supervision trees dynamically on the local BEAM node.

  The supervisor starts empty. Concrete Run supervision trees will be added
  only after durable Run ownership and lifecycle semantics are materialized.
  """

  use DynamicSupervisor

  @doc """
  Starts the Run dynamic supervisor.

  ## Parameters

  * `opts` - Startup options reserved for OTP supervision

  ## Returns

  * `{:ok, pid}` when the supervisor starts successfully
  * `{:error, reason}` when the supervisor cannot be started

  ## Examples

      iex> Process.whereis(LeafcutterRuntime.RunDynamicSupervisor) |> is_pid()
      true

  ## Notes

  * The supervisor is local to one BEAM node.
  * Run ownership is not determined by this process.
  * PostgreSQL will remain the durable authority for Run ownership and fencing.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
