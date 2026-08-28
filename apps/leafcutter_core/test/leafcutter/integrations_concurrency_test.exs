defmodule Leafcutter.IntegrationsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Catalog.Package
  alias Leafcutter.Catalog.Packages
  alias Leafcutter.Integrations
  alias Leafcutter.Integrations.Integration
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Repo

  test "Integration creation observes a concurrent Organization disable" do
    scope = persist_scope("Organization disable")
    on_exit(fn -> delete_scope(scope) end)

    pause_next_query("FOR UPDATE")

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Organizations.disable(scope.organization.id)
        end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    create_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Integrations.create(integration_attrs(scope))
        end)
      end)

    assert Task.yield(create_task, 100) == nil
    send(disable_process, :continue_query)

    assert {:ok, %Organization{disabled_at: %DateTime{}}} =
             Task.await(disable_task)

    assert {:error, :organization_disabled} = Task.await(create_task)
  end

  test "concurrent Integration disables preserve one lifecycle timestamp" do
    scope = persist_scope("Integration disable")

    integration =
      with_unboxed_connection(fn ->
        {:ok, integration} =
          Integrations.create(integration_attrs(scope))

        integration
      end)

    on_exit(fn -> delete_scope(scope) end)

    pause_next_query("FOR UPDATE")

    first_disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Integrations.disable(integration.id)
        end)
      end)

    assert_receive {:row_locked, first_disable_process}, 1_000

    second_disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Integrations.disable(integration.id)
        end)
      end)

    assert Task.yield(second_disable_task, 100) == nil
    send(first_disable_process, :continue_query)

    assert {:ok, first_disable} = Task.await(first_disable_task)
    assert {:ok, second_disable} = Task.await(second_disable_task)
    assert second_disable.disabled_at == first_disable.disabled_at
  end

  defp persist_scope(prefix) do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, organization} =
        Organizations.create(%{name: "#{prefix} #{suffix}"})

      {:ok, package} = Packages.create(%{name: "Package #{suffix}"})

      %{organization: organization, package: package}
    end)
  end

  defp integration_attrs(scope) do
    %{
      organization_id: scope.organization.id,
      package_id: scope.package.id,
      name: "Integration"
    }
  end

  defp pause_next_query(pattern) do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata, {test_process, handler_id, pattern} ->
          if String.contains?(metadata.query, pattern) do
            :telemetry.detach(handler_id)
            send(test_process, {:row_locked, self()})

            receive do
              :continue_query -> :ok
            after
              1_000 -> raise "timed out while holding a row lock"
            end
          end
        end,
        {test_process, handler_id, pattern}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp with_unboxed_connection(function) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      function.()
    after
      :ok = Sandbox.checkin(Repo)
    end
  end

  defp delete_scope(scope) do
    with_unboxed_connection(fn ->
      Integration
      |> where(
        [integration],
        integration.organization_id == ^scope.organization.id
      )
      |> Repo.delete_all()

      Organization
      |> where([organization], organization.id == ^scope.organization.id)
      |> Repo.delete_all()

      Package
      |> where([package], package.id == ^scope.package.id)
      |> Repo.delete_all()
    end)
  end
end
