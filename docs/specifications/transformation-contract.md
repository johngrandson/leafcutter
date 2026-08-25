# Transformation Contract

- Status: Accepted baseline

Transformation receives a source payload that already passed Contract validation and optional immutable configuration.

```elixir
@callback transform(payload :: map(), config :: map()) ::
  {:ok, map()}
  | {:ok, [map()]}
  | :skip
  | {:error, reason :: term()}
```

A versão exata do callback pode usar arity 1 quando config não é necessária. A implementação não executa side effects.

```text
1 -> 1
1 -> N
1 -> 0
```

N->1, joins e windowed aggregation não pertencem a esta primitive.
