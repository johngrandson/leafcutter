# Quality gates

## Gate agregado

```bash
mix quality
```

O alias atual executa:

```text
python3 -m unittest discover -s docs/scripts -p test_*.py
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test
mix dialyzer
```

Os dois primeiros comandos validam a base de conhecimento uma única vez na
raiz da umbrella, antes da compilação: primeiro a suíte de testes unitários do
linter e depois o lint estrito da base real. O ambiente precisa disponibilizar
Python 3; o linter e seus testes usam apenas a biblioteca padrão, sem pacotes
externos.

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
