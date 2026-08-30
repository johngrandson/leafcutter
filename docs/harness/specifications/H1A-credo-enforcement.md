# H1A: enforcement de specs e riscos objetivos no Credo

> **Status: APROVADA NO TRILHO ALTERNATIVO.** Esta specification detalha o
> subincremento H1A do harness. Ela não altera a sequência de produto nem
> `docs/checkpoint/CURRENT.md`.

## Objetivo

Fazer `mix quality` rejeitar funções públicas sem `@spec`, conversões inseguras
que criam atoms em runtime e testes ignorados sem comentário explicativo. O
incremento usa somente a configuração versionada do Credo já instalado e não
adiciona dependency, checker próprio ou nova etapa ao alias.

## Ownership e fontes de verdade

```text
mix.exs
└── ordem executável do alias mix quality

.credo.exs
└── seleção e parâmetros dos checks executados por mix credo --strict

docs/implementation/quality-gates.md
└── descrição operacional para pessoas e agentes
```

O alias raiz continua sendo a única entrada agregada. Skills em
`.claude/skills/` permanecem adapters e não repetem regras do Credo.

## Estado de entrada

O lockfile fixa Credo `1.7.19`. Sem `.credo.exs`, `mix credo --strict` usa a
configuração padrão da dependency e passa sobre 172 arquivos. Os três checks
deste incremento estão desabilitados por padrão.

Medições reproduzidas em 2026-08-30:

- `Credo.Check.Readability.Specs` encontra 12 definições públicas sem spec;
- `Credo.Check.Warning.UnsafeToAtom` não encontra ocorrência atual;
- `Credo.Check.Design.SkipTestWithoutComment` não encontra ocorrência atual.

Os comandos de medição usam `--enable-disabled-checks` apenas para auditar o
estado de entrada. A configuração materializada precisa tornar esses flags
desnecessários.

## Configuração versionada

Criar `.credo.exs` a partir da configuração gerada pelo Credo `1.7.19`. A lista
`enabled` preserva os checks padrão dessa versão e recebe somente:

```elixir
{Credo.Check.Design.SkipTestWithoutComment, []}
{Credo.Check.Readability.Specs, [include_defp: false]}
{Credo.Check.Warning.UnsafeToAtom, []}
```

Esses três checks saem da lista `disabled`. Nenhum outro check opt-in entra em
H1A. Os demais checks e seus parâmetros continuam iguais aos defaults gerados
para `1.7.19`.

Manter a configuração completa torna a seleção revisável e estável. Um upgrade
do Credo não incorpora silenciosamente mudanças na lista default; a atualização
da dependency e da configuração precisa acontecer no mesmo review quando essa
mudança for desejada.

`include_defp: false` limita `Credo.Check.Readability.Specs` a funções públicas.
Funções privadas continuam cobertas pelo Dialyzer quando seus fluxos alcançam
as APIs analisadas, mas não recebem specs apenas para satisfazer lint.

## Ausências de specs a corrigir

H1A adiciona typespecs sem mudar corpo, visibilidade ou retorno das funções
existentes:

| Módulo | Funções |
|---|---|
| `LeafcutterRuntime.ResolutionFixtures` | `deployment_fixture/0`, `deployment_fixture/1`, `delete_persisted_fixture/1` |
| `LeafcutterApi.Telemetry` | `start_link/1`, `metrics/0` |
| `LeafcutterApi.ErrorJSON` | `render/2` |
| `LeafcutterApi` | `static_paths/0`, `router/0`, `channel/0`, `controller/0`, `verified_routes/0` |
| `LeafcutterRuntime` | `hello/0` |
| `LeafcutterCore` | `hello/0` |

O Credo reporta 12 definições. `deployment_fixture/1` possui argumento default,
por isso o contrato precisa declarar também a aridade pública `/0`.

### Precisão esperada

- `ResolutionFixtures` define um tipo de fixture com as chaves e schemas que o
  helper realmente retorna; `map()` não substitui essa shape conhecida;
- `start_link/1` usa `Supervisor.on_start()` e `metrics/0` retorna
  `[Telemetry.Metrics.t()]`;
- `ErrorJSON.render/2` declara o envelope `%{errors: %{detail: String.t()}}`;
- helpers de `LeafcutterApi` distinguem a lista de paths de `Macro.t()`;
- os dois helpers `hello/0` retornam o literal `:world`.

H1A não cria docs públicas novas, não remove scaffolding existente e não amplia
o escopo para specs de funções privadas.

## Prova negativa reproduzível

Antes de criar `.credo.exs`, adicionar temporariamente um arquivo incluído pelo
Credo com as três violações:

```elixir
defmodule H1ACredoNegativeFixtureTest do
  use ExUnit.Case

  def unsafe_atom(value), do: String.to_atom(value)

  @tag :skip
  test "requires a reason for a skipped test" do
    assert true
  end
end
```

Executar o Credo somente sobre esse arquivo. Sem a configuração, o comando sai
com status `0`, provando a ausência do enforcement:

```bash
mix credo suggest \
  apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs \
  --strict --format json
```

Depois de criar `.credo.exs`, o mesmo comando precisa sair com status diferente
de `0`. O JSON precisa identificar exatamente os checks
`Credo.Check.Readability.Specs`, `Credo.Check.Warning.UnsafeToAtom` e
`Credo.Check.Design.SkipTestWithoutComment`. Essa prova executa o consumidor
real da configuração; ela não valida o arquivo por busca textual.

O arquivo temporário é removido antes do commit. Em seguida, a primeira execução
com a configuração real precisa falhar pelas 12 ausências conhecidas. Depois da
correção, `mix credo --strict` passa sem `--enable-disabled-checks`.

## Documentação e estado

Ao materializar H1A:

- `docs/implementation/quality-gates.md` registra que a etapa Credo carrega a
  configuração versionada e nomeia os três checks opt-in;
- `docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md` marca somente H1A como
  materializado e mantém H1B a H1E pendentes;
- esta specification recebe o estado materializado e aponta para a evidência;
- `docs/checkpoint/CURRENT.md` e documentos de produto não mudam.

O ADR-0015 já define `mix quality` como gate compartilhado. H1A materializa uma
parte desse gate sem alterar a decisão, portanto não exige novo ADR.

## Fora de escopo

- habilitar todos os checks controversos ou experimentais do Credo;
- exigir specs de funções privadas;
- criar checker customizado;
- alterar a ordem ou as etapas do alias `mix quality`;
- adicionar dependency;
- implementar os gates H1B a H1E;
- criar pre-commit, CI ou adapter de skill;
- alterar código de domínio, persistência, processos OTP ou contracts externos;
- atualizar `CURRENT.md`.

## Critérios de aceitação

- `.credo.exs` preserva os defaults gerados do Credo `1.7.19` e habilita somente
  os três checks opt-in definidos nesta specification;
- a prova temporária falha pelas três violações após a configuração e o arquivo
  de prova não existe no diff final;
- as 12 definições reportadas recebem specs compatíveis com seus retornos reais;
- `mix credo --strict` passa sem flags de opt-in;
- `docs/implementation/quality-gates.md` e o roadmap descrevem apenas o estado
  materializado;
- nenhum comportamento de produto, migration, schema, context ou checkpoint
  muda;
- `git diff --check` e `mix quality` passam.
