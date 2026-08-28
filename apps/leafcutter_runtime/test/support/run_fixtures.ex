defmodule Leafcutter.Executions.RunFixtures do
  @moduledoc false

  alias Leafcutter.Executions.{Run, Runs}

  @doc "Creates a pending Run through the public API with an eligible snapshot."
  @spec pending_run_fixture() :: Run.t()
  def pending_run_fixture do
    {:ok, run} = Runs.create(definition_fixture())
    run
  end

  @doc "Builds a structurally valid RunSnapshot definition v1."
  @spec definition_fixture() :: map()
  def definition_fixture do
    %{
      "package_version_id" => Ecto.UUID.generate(),
      "source" => %{
        "ref" => "source",
        "contract_version_id" => Ecto.UUID.generate(),
        "connection" => %{
          "id" => Ecto.UUID.generate(),
          "config" => %{},
          "secret_version_id" => nil
        }
      },
      "destinations" => [
        %{
          "ref" => "destination",
          "contract_version_id" => Ecto.UUID.generate(),
          "connection" => %{
            "id" => Ecto.UUID.generate(),
            "config" => %{},
            "secret_version_id" => nil
          }
        }
      ],
      "effective_config" => %{}
    }
  end
end
