# LeafcutterConnectors

Owns executable connector contracts and their bounded transport boundaries.

The application supervises the shared HTTP/1 Finch client used by connector
packages. It does not depend on Catalog, Ecto, Repo, or runtime internals.
