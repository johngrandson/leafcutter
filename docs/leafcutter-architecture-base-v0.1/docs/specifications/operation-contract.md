# Operation Contract

- Status: Accepted baseline

## Read

```elixir
@callback fetch(configuration(), cursor()) ::
  {:ok, page_result()}
  | {:error, OperationError.t()}
```

`page_result` normaliza:

```text
records
next_cursor
done?
metadata
```

## Write

```elixir
@callback deliver([payload()], configuration()) ::
  {:ok, [item_result()]}
  | {:error, OperationError.t()}
```

`item_result` preserva sucesso/falha individual e Destination Identity quando disponível.

A Operation não controla Broadway, não agenda retry e não acessa configuração de tenant fora da Connection recebida.
