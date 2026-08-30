# Quality gates

`mix.exs` define o comportamento executável do gate. Este documento é sua
descrição operacional canônica para pessoas e agentes.

## Gate agregado

```bash
mix quality
```

O alias atual executa:

```text
python3 -m unittest discover -s docs/scripts -p test_*.py
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
mix compile --warnings-as-errors
compiled package inventory + Mix release closure validation
mix format --check-formatted
mix credo --strict
mix test
mix dialyzer
for each package in packages/build.exs:
  MIX_ENV=test mix compile --warnings-as-errors
  MIX_ENV=test mix format --check-formatted
  MIX_ENV=test mix test
  MIX_ENV=test mix dialyzer
```

O alias raiz de `compile` materializa primeiro `leafcutter_connectors`. O Mix
compila path dependencies externas antes dos filhos da umbrella; essa ordenação
explícita garante que packages instalados encontrem os contracts públicos de
Connectors mesmo com `_build` vazio. A compilação normal da umbrella continua em
seguida e preserva o mesmo dependency graph.

Os dois primeiros comandos validam a base de conhecimento uma única vez na
raiz da umbrella, antes da compilação: primeiro a suíte de testes unitários do
linter e depois o lint estrito da base real. O ambiente precisa disponibilizar
Python 3; o linter e seus testes usam apenas a biblioteca padrão, sem pacotes
externos.

Esses comandos formam o enforcement automático materializado. Reviews humanos
continuam responsáveis pelas regras que não possuem checker objetivo.

Depois da compilação, o gate exige que Core, Connectors, Runtime, API e todos os
apps da inventory pertençam à application closure produzida por `Mix.Release`.
Os comandos por package são executados no próprio Mix project porque testes e
Dialyzer de dependencies não são herdados pela suíte da umbrella. Com a
inventory de produção vazia, esse loop termina sem executar subprojetos; a
fixture de conformance continua coberta pela suíte do runtime.

### Configuração do Credo

A etapa `mix credo --strict` carrega `.credo.exs`. Além dos checks padrão
fixados para o Credo 1.7.19, a configuração habilita somente estes checks
opt-in:

```text
Credo.Check.Design.SkipTestWithoutComment
Credo.Check.Readability.Specs com include_defp: false
Credo.Check.Warning.UnsafeToAtom
```

O check de specs cobre funções públicas. Checks controversos ou experimentais
adicionais exigem um incremento próprio com prova negativa.

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

Checks focados reduzem o tempo de feedback. Eles não substituem o gate
agregado.

Antes de cada commit, execute o gate completo.

## Verificações manuais de review

Para mudanças arquiteturais, revisar manualmente:

```text
decisões ratificadas e escopo autorizado
ownership e APIs públicas entre contexts
necessidade de processos OTP e abstrações
CURRENT.md e estado atual/visão futura
ADR, specification e contracts afetados
exposição de segredos ou dados sensíveis
```

O checklist detalhado está em `docs/harness/REVIEW_CHECKLIST.md`.

## Critério

Não declarar conclusão com warning, skip desnecessário ou Dialyzer pendente. Falhas de banco/test environment devem ser reportadas explicitamente, não mascaradas.
