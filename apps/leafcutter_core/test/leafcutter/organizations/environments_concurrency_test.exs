defmodule Leafcutter.Organizations.EnvironmentsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environment
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Repo

  test "environment creation observes a concurrent organization disable" do
    organization_name = "Concurrent #{System.unique_integer([:positive])}"

    organization =
      with_unboxed_connection(fn ->
        {:ok, organization} = Organizations.create(%{name: organization_name})
        organization
      end)

    on_exit(fn -> delete_organization(organization.id) end)

    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata, {test_process, handler_id} ->
          if String.contains?(metadata.query, "FOR UPDATE") do
            :telemetry.detach(handler_id)
            send(test_process, {:organization_locked, self()})

            receive do
              :continue_disable -> :ok
            after
              1_000 -> raise "timed out while holding the organization lock"
            end
          end
        end,
        {test_process, handler_id}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Organizations.disable(organization.id) end)
      end)

    assert_receive {:organization_locked, disable_process}, 1_000

    environment_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Environments.create(%{
            organization_id: organization.id,
            name: "Production"
          })
        end)
      end)

    assert Task.yield(environment_task, 100) == nil

    send(disable_process, :continue_disable)

    assert {:ok, %Organization{disabled_at: %DateTime{}}} = Task.await(disable_task)
    assert {:error, :organization_disabled} = Task.await(environment_task)
  end

  defp with_unboxed_connection(function) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      function.()
    after
      :ok = Sandbox.checkin(Repo)
    end
  end

  defp delete_organization(organization_id) do
    with_unboxed_connection(fn ->
      Environment
      |> where([environment], environment.organization_id == ^organization_id)
      |> Repo.delete_all()

      Organization
      |> where([organization], organization.id == ^organization_id)
      |> Repo.delete_all()
    end)
  end
end
