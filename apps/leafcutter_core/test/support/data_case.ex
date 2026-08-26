defmodule Leafcutter.DataCase do
  @moduledoc """
  Test case for code that interacts with the shared repository.

  Each test owns an isolated SQL Sandbox connection so database changes are
  rolled back when the test exits.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset

  using do
    quote do
      alias Leafcutter.Repo

      import Leafcutter.DataCase
    end
  end

  setup tags do
    owner =
      Sandbox.start_owner!(Leafcutter.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  @doc """
  Converts changeset errors into a map keyed by field.
  """
  @spec errors_on(Changeset.t()) :: %{optional(atom()) => [String.t()]}
  def errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
