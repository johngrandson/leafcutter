defmodule LeafcutterRuntime.RunSupervisor do
  @moduledoc """
  Supervises the local control-plane tree for one durably owned Run.

  The supervisor is registered locally by Run identifier and retains the
  ownership token as Registry metadata. PostgreSQL remains the authority for
  ownership; this process only represents the current local incarnation of the
  Run tree.
  """

  use Supervisor

  alias Leafcutter.Executions.{Run, Runs}
  alias LeafcutterRuntime.RunCoordinator

  @doc """
  Returns the dynamic child specification for one Run supervision tree.

  ## Parameters

  * `ownership_token` - The durable Run ownership token acquired before startup

  ## Returns

  * A transient supervisor child specification keyed by the Run identifier

  ## Examples

      iex> token = %{
      ...>   run_id: Ecto.UUID.generate(),
      ...>   runtime_node_id: Ecto.UUID.generate(),
      ...>   generation: 1
      ...> }

      iex> %{type: :supervisor, restart: :transient} =
      ...>   LeafcutterRuntime.RunSupervisor.child_spec(token)

  ## Notes

  * Abnormal supervisor exits may be restarted with the same ownership token.
  * Normal or shutdown exits are not restarted by the Run dynamic supervisor.
  * A fresh durable claim is required before starting a later generation.
  """
  @spec child_spec(Runs.ownership_token()) :: Supervisor.child_spec()
  def child_spec(ownership_token) do
    %{
      id: {__MODULE__, ownership_token.run_id},
      start: {__MODULE__, :start_link, [ownership_token]},
      restart: :transient,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @doc """
  Starts a supervisor for one durably owned Run.

  ## Parameters

  * `ownership_token` - The current fencing token returned by `Executions.Runs.claim/2`

  ## Returns

  * `{:ok, pid}` when the Run supervisor starts
  * `{:error, {:already_started, pid}}` when the Run is already registered locally
  * `{:error, reason}` when startup fails

  ## Examples

      iex> is_pid(Process.whereis(LeafcutterRuntime.RunDynamicSupervisor))
      true

  ## Notes

  * Callers must claim durable ownership before invoking this function.
  * The Registry key is the Run identifier and its value is the ownership token.
  * Direct callers should normally use `LeafcutterRuntime.Runs.start/1` instead.
  """
  @spec start_link(Runs.ownership_token()) :: Supervisor.on_start()
  def start_link(ownership_token) do
    Supervisor.start_link(
      __MODULE__,
      ownership_token,
      name: via_name(ownership_token)
    )
  end

  @impl true
  @spec init(Runs.ownership_token()) ::
          {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(ownership_token) do
    coordinator =
      Supervisor.child_spec(
        {RunCoordinator, ownership_token},
        restart: :transient,
        significant: true
      )

    Supervisor.init(
      [coordinator],
      strategy: :one_for_one,
      auto_shutdown: :any_significant
    )
  end

  @spec via_name(Runs.ownership_token()) ::
          {:via, Registry, {atom(), Run.id(), Runs.ownership_token()}}
  defp via_name(ownership_token) do
    {:via, Registry,
     {
       LeafcutterRuntime.RunRegistry,
       ownership_token.run_id,
       ownership_token
     }}
  end
end
