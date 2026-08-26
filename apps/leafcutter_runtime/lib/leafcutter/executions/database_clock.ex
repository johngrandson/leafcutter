defmodule Leafcutter.Executions.DatabaseClock do
  @moduledoc false

  alias Leafcutter.Repo

  @doc false
  @spec now() :: DateTime.t()
  def now do
    %{rows: [[%DateTime{} = timestamp]]} =
      Repo.query!("SELECT clock_timestamp()", [])

    timestamp
  end
end
