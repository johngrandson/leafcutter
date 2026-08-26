defmodule LeafcutterRuntime.RunDynamicSupervisor do
  @moduledoc """
  Supervises per-Run control-plane trees dynamically on the local BEAM node.

  Each child is a `LeafcutterRuntime.RunSupervisor` started only after durable
  ownership has been claimed. The supervisor is local and does not decide
  ownership, recovery, or fencing; PostgreSQL remains authoritative for those
  concerns.
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
  * Children are transient per-Run supervisors keyed through the local Registry.
  * Durable claim must complete before a Run tree is added.
  * Direct callers should normally use `LeafcutterRuntime.Runs.start/1`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  @spec init(:ok) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
