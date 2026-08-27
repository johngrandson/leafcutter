# Quality gates

## Gate agregado

```bash
mix quality
```

O alias atual executa:

```text
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test
mix dialyzer
```

## Mudanças com migration

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
mix quality
```

## Durante desenvolvimento

Use o menor gate que produza feedback útil:

```bash
mix format
mix compile --warnings-as-errors
mix test path/to/relevant_test.exs
```

Antes do merge, execute o gate completo.

## Verificações documentais

Para mudanças arquiteturais, revisar manualmente:

```text
CURRENT.md
architecture/estado-atual-e-visao-futura.md
ADR related
specification related
public docs/examples
```

## Critério

Não declarar conclusão com warning, skip desnecessário ou Dialyzer pendente. Falhas de banco/test environment devem ser reportadas explicitamente, não mascaradas.
