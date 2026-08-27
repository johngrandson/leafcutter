defmodule Leafcutter.Executions.RunSnapshot do
  @moduledoc """
  Represents the immutable, versioned definition persisted for one execution Run.

  The Run identifier is also the snapshot primary key. Snapshots do not have an
  independent identity or timestamps, and the database rejects every update
  after insertion.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Executions.Run
  alias Leafcutter.Executions.RunSnapshot.DefinitionV1

  @primary_key {:run_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  @current_format_version 1
  @supported_format_versions [@current_format_version]
  @creation_fields [:run_id, :definition]

  @typedoc "The positive version that selects the persisted definition decoder."
  @type format_version :: pos_integer()

  @typedoc "The JSON-compatible definition frozen for one Run."
  @type definition :: DefinitionV1.normalized_definition()

  @typedoc "Attributes accepted when creating an immutable RunSnapshot."
  @type create_attrs ::
          %{
            required(:run_id) => Run.id(),
            required(:definition) => map()
          }
          | %{required(String.t()) => term()}

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

  @doc """
  Returns the format version assigned to newly created RunSnapshots.

  Persisted snapshots retain their original format version and are never
  rewritten in place.
  """
  @spec current_format_version() :: format_version()
  def current_format_version, do: @current_format_version

  @doc """
  Returns the RunSnapshot format versions understood by this runtime.

  This list is used by the control plane to decide whether a pending Run is
  eligible to start.
  """
  @spec supported_format_versions() :: [format_version()]
  def supported_format_versions, do: @supported_format_versions

  @doc """
  Builds the changeset used to create an immutable RunSnapshot.

  ## Parameters

  * snapshot - The new RunSnapshot schema
  * attrs - The Run identifier and complete logical definition

  ## Returns

  * A valid changeset containing the canonical v1 definition
  * An invalid changeset when required fields or the v1 structure are invalid

  ## Examples

      iex> run_id = Ecto.UUID.generate()
      iex> definition = %{
      ...>   package_version_id: Ecto.UUID.generate(),
      ...>   source: %{
      ...>     ref: "source",
      ...>     contract_version_id: Ecto.UUID.generate(),
      ...>     connection: %{
      ...>       id: Ecto.UUID.generate(),
      ...>       config: %{},
      ...>       secret_version_id: nil
      ...>     }
      ...>   },
      ...>   destinations: [
      ...>     %{
      ...>       ref: "destination",
      ...>       contract_version_id: Ecto.UUID.generate(),
      ...>       connection: %{
      ...>         id: Ecto.UUID.generate(),
      ...>         config: %{},
      ...>         secret_version_id: nil
      ...>       }
      ...>     }
      ...>   ],
      ...>   effective_config: %{}
      ...> }
      iex> changeset =
      ...>   Leafcutter.Executions.RunSnapshot.create_changeset(
      ...>     %Leafcutter.Executions.RunSnapshot{},
      ...>     %{run_id: run_id, definition: definition}
      ...>   )
      iex> changeset.valid?
      true
      iex> Ecto.Changeset.get_change(changeset, :format_version)
      1

  ## Notes

  * The caller cannot choose format_version; the current version is assigned internally.
  * Definition v1 is structurally validated and normalized before persistence.
  * Referenced entity existence and raw-secret detection remain outside this changeset.
  * Database constraints protect Run existence, uniqueness, positive version, and JSON root shape.
  * There is intentionally no update changeset for an immutable snapshot.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @creation_fields)
    |> validate_required(@creation_fields)
    |> validate_definition()
    |> put_change(:format_version, current_format_version())
    |> foreign_key_constraint(:run_id)
    |> unique_constraint(:run_id, name: :run_snapshots_pkey)
    |> check_constraint(
      :format_version,
      name: :run_snapshots_format_version_positive
    )
    |> check_constraint(
      :definition,
      name: :run_snapshots_definition_is_object
    )
  end

  @spec validate_definition(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_definition(changeset) do
    case fetch_change(changeset, :definition) do
      {:ok, definition} ->
        case DefinitionV1.validate(definition) do
          {:ok, normalized_definition} ->
            put_change(changeset, :definition, normalized_definition)

          {:error, definition_changeset} ->
            add_error(
              changeset,
              :definition,
              "is invalid",
              validation: :run_snapshot_definition_v1,
              definition_errors:
                traverse_errors(definition_changeset, fn {message, options} ->
                  {message, options}
                end)
            )
        end

      :error ->
        changeset
    end
  end
end
