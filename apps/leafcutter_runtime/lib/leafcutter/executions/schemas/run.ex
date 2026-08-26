defmodule Leafcutter.Executions.Run do
  @moduledoc """
  Represents the durable lifecycle and ownership state of an execution Run.

  PostgreSQL is the authority for Run ownership. `generation` is a monotonic
  fencing token that changes whenever a new runtime node incarnation acquires
  the Run.

  This initial schema deliberately excludes executable configuration and
  snapshot references. A public Run creation workflow will be added only after
  those domain contracts are ratified.
  """

  use Ecto.Schema

  alias Leafcutter.Executions.RuntimeNode

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @statuses [:pending, :running, :completed, :failed, :cancelled]

  @typedoc "The durable Run identifier."
  @type id :: Ecto.UUID.t()

  @typedoc "The initial lifecycle states recognized by the Run ownership foundation."
  @type status ::
          :pending
          | :running
          | :completed
          | :failed
          | :cancelled

  @typedoc "A durable Run with optional ownership by one runtime incarnation."
  @type t :: %__MODULE__{
          id: id() | nil,
          status: status(),
          owner_node_id: RuntimeNode.id() | nil,
          owner_node: RuntimeNode.t() | Ecto.Association.NotLoaded.t() | nil,
          generation: non_neg_integer(),
          ownership_acquired_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "runs" do
    field(:status, Ecto.Enum, values: @statuses, default: :pending)

    belongs_to(:owner_node, RuntimeNode)

    field(:generation, :integer, default: 0)
    field(:ownership_acquired_at, :utc_datetime_usec)

    timestamps()
  end
end
