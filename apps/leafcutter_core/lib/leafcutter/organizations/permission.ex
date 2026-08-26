defmodule Leafcutter.Organizations.Permission do
  @moduledoc """
  Defines the permissions recognized by the Organizations context.

  Permissions are represented as typed atoms inside the domain and as
  stable string identifiers at persistence and external boundaries.
  """

  @type t ::
          :organization_read
          | :organization_manage
          | :environment_read
          | :environment_manage
          | :access_manage

  @permissions [
    organization_read: "organization.read",
    organization_manage: "organization.manage",
    environment_read: "environment.read",
    environment_manage: "environment.manage",
    access_manage: "access.manage"
  ]

  @doc """
  Returns all permissions recognized by the Organizations context.

  ## Returns

  * A non-empty list containing every known permission

  ## Examples

      iex> :access_manage in Leafcutter.Organizations.Permission.all()
      true

  ## Notes

  * The returned atoms are the canonical domain representation.
  * Adding a permission is an explicit source-code change.
  """
  @spec all() :: nonempty_list(t())
  def all do
    Keyword.keys(@permissions)
  end

  @doc """
  Returns the stable string identifier for a permission.

  ## Parameters

  * `permission` - The domain permission to convert

  ## Returns

  * The stable external and persistence identifier for the permission

  ## Examples

      iex> Leafcutter.Organizations.Permission.identifier(:access_manage)
      "access.manage"

  ## Notes

  * Identifiers are persisted and may become part of external API contracts.
  * Existing identifiers must not be renamed casually.
  """
  @spec identifier(t()) :: String.t()
  def identifier(permission) do
    Keyword.fetch!(@permissions, permission)
  end

  @doc """
  Parses a permission identifier into its domain representation.

  ## Parameters

  * `identifier` - The external or persisted permission identifier

  ## Returns

  * `{:ok, permission}` when the identifier is known
  * `{:error, :unknown_permission}` when the identifier is not recognized

  ## Examples

      iex> Leafcutter.Organizations.Permission.parse("environment.read")
      {:ok, :environment_read}

      iex> Leafcutter.Organizations.Permission.parse("unknown.permission")
      {:error, :unknown_permission}

  ## Notes

  * Parsing is explicit so arbitrary strings do not enter authorization logic.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, :unknown_permission}
  def parse(identifier) do
    case Enum.find(@permissions, fn {_permission, value} -> value == identifier end) do
      {permission, _identifier} ->
        {:ok, permission}

      nil ->
        {:error, :unknown_permission}
    end
  end
end
