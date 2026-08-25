# Leafcutter

**TODO: Add description**

## Tidewave

Tidewave runs once at the umbrella root, so every child application is loaded
into the runtime it inspects, including applications added later:

```sh
mix tidewave
```

The MCP endpoint is `http://localhost:4001/tidewave/mcp`. Set
`TIDEWAVE_PORT` before running the command to use a different port.

The dependency is development-only and is not included in production. If a
future Phoenix endpoint needs Tidewave's in-page toolbar and browser tooling,
add Tidewave to that endpoint application's development dependencies and mount
`plug Tidewave` there, following the Tidewave Phoenix installation guide. For
LiveView source mapping, enable `debug_heex_annotations` and `debug_attributes`
in the shared development configuration when LiveView is added to the umbrella.
