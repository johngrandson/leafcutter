defmodule Leafcutter.Executions.DatabaseClock do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Leafcutter.Repo

  @doc false
  @spec now() :: DateTime.t()
  def now do
    %{rows: [[%DateTime{} = timestamp]]} =
      SQL.query!(Repo, "SELECT clock_timestamp()", [])

    timestamp
  end
end
