defmodule Leafcutter.Executions.RunSnapshot do
  @moduledoc """
  Represents the immutable, versioned definition persisted for one execution Run.

  The Run identifier is also the snapshot primary key. Snapshots do not have an
  independent identity or timestamps, and the database rejects every update
  after insertion.
  """

  use Ecto.Schema

  alias Leafcutter.Executions.Run

  @primary_key {:run_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @typedoc "The positive version that selects the persisted definition decoder."
  @type format_version :: pos_integer()

  @typedoc "The JSON-compatible definition frozen for one Run."
  @type definition :: map()

  @typedoc "An immutable definition snapshot associated with one Run."
  @type t :: %__MODULE__{
          run_id: Run.id() | nil,
          run: Run.t() | Ecto.Association.NotLoaded.t(),
          format_version: format_version() | nil,
          definition: definition() | nil
        }

  schema "run_snapshots" do
    belongs_to(:run, Run, define_field: false, foreign_key: :run_id)

    field(:format_version, :integer)
    field(:definition, :map)
  end
end
