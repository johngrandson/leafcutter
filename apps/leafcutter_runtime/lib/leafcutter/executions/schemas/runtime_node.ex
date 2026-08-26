defmodule Leafcutter.Executions.RuntimeNode do
  @moduledoc """
  Represents one running incarnation of the Leafcutter BEAM runtime.

  Runtime node identity is independent from the Erlang node name. A new
  application start receives a new identifier even when it reuses the same
  `node()` value.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @required_fields [:id, :node_name, :last_heartbeat_at]

  @typedoc "The identifier of one specific runtime incarnation."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when recording a runtime node heartbeat."
  @type heartbeat_attrs :: %{
          required(:id) => id(),
          required(:node_name) => String.t(),
          required(:last_heartbeat_at) => DateTime.t()
        }

  @typedoc "A durable runtime node liveness record."
  @type t :: %__MODULE__{
          id: id() | nil,
          node_name: String.t() | nil,
          last_heartbeat_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "runtime_nodes" do
    field(:node_name, :string)
    field(:last_heartbeat_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for recording a runtime node heartbeat.

  ## Parameters

  * `runtime_node` - The runtime node schema receiving the heartbeat attributes
  * `attrs` - The incarnation identifier, Erlang node name, and heartbeat timestamp

  ## Returns

  * A valid changeset when all heartbeat attributes satisfy the runtime node constraints
  * An invalid changeset when required attributes are missing or malformed

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Executions.RuntimeNode.heartbeat_changeset(
      ...>     %Leafcutter.Executions.RuntimeNode{},
      ...>     %{
      ...>       id: Ecto.UUID.generate(),
      ...>       node_name: "leafcutter@host-1",
      ...>       last_heartbeat_at: DateTime.utc_now(:microsecond)
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> Leafcutter.Executions.RuntimeNode.heartbeat_changeset(
      ...>   %Leafcutter.Executions.RuntimeNode{},
      ...>   %{id: Ecto.UUID.generate()}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * `id` identifies one application incarnation and is generated outside the schema.
  * `node_name` is metadata and is deliberately not unique.
  * Reusing a node name after a restart must not revive ownership held by an older incarnation.
  * Node names may contain at most 255 characters.
  """
  @spec heartbeat_changeset(t(), heartbeat_attrs()) :: Ecto.Changeset.t()
  def heartbeat_changeset(runtime_node, attrs) do
    runtime_node
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:node_name, max: 255)
  end
end
