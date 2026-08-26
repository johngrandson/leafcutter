defmodule Leafcutter.Organizations.User do
  @moduledoc """
  Represents a human user within Leafcutter.

  Users have a platform-wide identity and may participate in multiple
  organizations through memberships. Authentication mechanisms are
  intentionally outside this schema.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @email_regex ~r/^[^\s@]+@[^\s@]+$/

  @type id :: Ecto.UUID.t()

  @type create_attrs :: %{
          required(:email) => String.t()
        }

  @type t :: %__MODULE__{
          id: id() | nil,
          email: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field(:email, :string)
    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a user.

  ## Parameters

  * `user` - The user schema receiving the creation attributes
  * `attrs` - The attributes used to create the user

  ## Returns

  * A valid changeset when the email satisfies the required constraints
  * An invalid changeset when the email is missing or malformed

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.User.create_changeset(
      ...>     %Leafcutter.Organizations.User{},
      ...>     %{email: " User@Example.COM "}
      ...>   )

      iex> Ecto.Changeset.get_change(changeset, :email)
      "user@example.com"

      iex> Leafcutter.Organizations.User.create_changeset(
      ...>   %Leafcutter.Organizations.User{},
      ...>   %{email: "a@@b"}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

      iex> Leafcutter.Organizations.User.create_changeset(
      ...>   %Leafcutter.Organizations.User{},
      ...>   %{}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * Email addresses are trimmed and normalized to lowercase before persistence.
  * Email addresses are globally unique within the platform.
  * Email addresses may contain at most 320 characters.
  * `disabled_at` is not accepted during creation and defaults to `nil`.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> normalize_email()
    |> validate_required([:email])
    |> validate_length(:email, max: 320)
    |> validate_format(:email, @email_regex, message: "must be a valid email address")
    |> unique_constraint(:email)
  end

  @spec normalize_email(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_email(changeset) do
    update_change(changeset, :email, fn email ->
      email
      |> String.trim()
      |> String.downcase()
    end)
  end

  @doc """
  Builds a changeset for disabling a user.

  ## Parameters

  * `user` - The user whose lifecycle state will be changed

  ## Returns

  * A changeset containing a new `disabled_at` timestamp when the user is active
  * An unchanged changeset when the user is already disabled

  ## Examples

      iex> user = %Leafcutter.Organizations.User{}
      iex> changeset = Leafcutter.Organizations.User.disable_changeset(user)
      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Persistence and concurrency control are handled by the Organizations context,
    not by this changeset.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = user) do
    change(user, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = user) do
    change(user)
  end
end
