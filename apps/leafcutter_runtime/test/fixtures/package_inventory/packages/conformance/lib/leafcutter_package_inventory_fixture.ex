defmodule LeafcutterPackageInventoryFixture.Source do
  @moduledoc false

  @behaviour LeafcutterConnectors.Operation.Read

  alias LeafcutterConnectors.Operation.Read.{Invocation, Result}

  @impl true
  def read(%Invocation{}) do
    {:ok, %Result{records: [], next_cursor: nil}}
  end
end

defmodule LeafcutterPackageInventoryFixture.FirstDestination do
  @moduledoc false

  @behaviour LeafcutterConnectors.Operation.Write

  alias LeafcutterConnectors.Operation.Error
  alias LeafcutterConnectors.Operation.Write.Invocation

  @impl true
  def write(%Invocation{}) do
    {:error, %Error{category: :permanent, code: "fixture_failure"}}
  end
end

defmodule LeafcutterPackageInventoryFixture.SecondDestination do
  @moduledoc false

  @behaviour LeafcutterConnectors.Operation.Write

  alias LeafcutterConnectors.Operation.Error
  alias LeafcutterConnectors.Operation.Write.Invocation

  @impl true
  def write(%Invocation{}) do
    {:error, %Error{category: :permanent, code: "fixture_failure"}}
  end
end

defmodule LeafcutterPackageInventoryFixture.InvalidRead do
  @moduledoc false

  def read(_invocation), do: :invalid
end

defmodule LeafcutterPackageInventoryFixture.Package do
  @moduledoc false

  use LeafcutterConnectors.Package,
    manifest: Path.expand("../manifest.json", __DIR__),
    source: {"source", LeafcutterPackageInventoryFixture.Source},
    destinations: [
      {"warehouse", LeafcutterPackageInventoryFixture.FirstDestination},
      {"crm", LeafcutterPackageInventoryFixture.SecondDestination}
    ]
end

defmodule LeafcutterPackageInventoryFixture.OtherManifestPackage do
  @moduledoc false

  use LeafcutterConnectors.Package,
    manifest: Path.expand("../other_manifest.json", __DIR__),
    source: {"source", LeafcutterPackageInventoryFixture.Source},
    destinations: [
      {"first-destination", LeafcutterPackageInventoryFixture.FirstDestination},
      {"second-destination", LeafcutterPackageInventoryFixture.SecondDestination}
    ]
end

defmodule LeafcutterPackageInventoryFixture.InvalidOperationPackage do
  @moduledoc false

  @behaviour LeafcutterConnectors.Package
  @external_resource Path.expand("../manifest.json", __DIR__)

  alias LeafcutterPackageInventoryFixture.Package

  @impl true
  def manifest, do: Package.manifest()

  @impl true
  def manifest_sha256, do: Package.manifest_sha256()

  @impl true
  def source, do: {"source", LeafcutterPackageInventoryFixture.InvalidRead}

  @impl true
  def destinations do
    [
      {"warehouse", LeafcutterPackageInventoryFixture.FirstDestination},
      {"crm", LeafcutterPackageInventoryFixture.SecondDestination}
    ]
  end

  @impl true
  def resolve("source", :source), do: {:ok, LeafcutterPackageInventoryFixture.InvalidRead}

  def resolve("warehouse", :destination),
    do: {:ok, LeafcutterPackageInventoryFixture.FirstDestination}

  def resolve("crm", :destination),
    do: {:ok, LeafcutterPackageInventoryFixture.SecondDestination}

  def resolve(_ref, _role), do: {:error, :not_found}
end

defmodule LeafcutterPackageInventoryFixture.InvalidTopologyPackage do
  @moduledoc false

  @behaviour LeafcutterConnectors.Package
  @external_resource Path.expand("../manifest.json", __DIR__)

  alias LeafcutterPackageInventoryFixture.Package

  @impl true
  def manifest, do: Package.manifest()

  @impl true
  def manifest_sha256, do: Package.manifest_sha256()

  @impl true
  def source, do: {"wrong-source", LeafcutterPackageInventoryFixture.Source}

  @impl true
  def destinations do
    [
      {"crm", LeafcutterPackageInventoryFixture.SecondDestination},
      {"warehouse", LeafcutterPackageInventoryFixture.FirstDestination}
    ]
  end

  @impl true
  def resolve("wrong-source", :source),
    do: {:ok, LeafcutterPackageInventoryFixture.Source}

  def resolve("crm", :destination),
    do: {:ok, LeafcutterPackageInventoryFixture.SecondDestination}

  def resolve("warehouse", :destination),
    do: {:ok, LeafcutterPackageInventoryFixture.FirstDestination}

  def resolve(_ref, _role), do: {:error, :not_found}
end
