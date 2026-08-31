# Enforcement Credo H1A: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer `mix quality` rejeitar funções públicas sem spec, criação
insegura de atoms e testes ignorados sem explicação.

**Architecture:** O alias raiz continua chamando `mix credo --strict` na mesma
posição. Uma `.credo.exs` completa fixa os defaults do Credo 1.7.19 e habilita
somente os três checks aprovados. As definições já reportadas recebem specs sem
mudança de comportamento; depois, a documentação do trilho registra o estado
materializado.

**Tech Stack:** Elixir 1.19.5, Credo 1.7.19, Dialyzer, Mix, Markdown.

**Spec:** `docs/harness/specifications/H1A-credo-enforcement.md`.

## Global Constraints

- O lockfile permanece em Credo `1.7.19`; não adicionar ou atualizar
  dependencies.
- Preservar todos os checks e parâmetros gerados por `mix credo.gen.config`
  para Credo 1.7.19.
- Habilitar como opt-in somente
  `Credo.Check.Design.SkipTestWithoutComment`,
  `Credo.Check.Readability.Specs` e
  `Credo.Check.Warning.UnsafeToAtom`.
- Configurar `Credo.Check.Readability.Specs` com `include_defp: false`.
- Não mudar a ordem nem as etapas do alias `mix quality`.
- Não mudar corpos, visibilidade ou retorno das 12 definições corrigidas.
- Todo código, typespec e nome de fixture permanece em inglês. Documentação do
  trilho permanece em português brasileiro.
- O arquivo negativo é temporário e não pode existir no diff final.
- Não alterar `docs/checkpoint/CURRENT.md`, ADRs de produto, schemas,
  migrations, contexts ou processos OTP.
- Preservar mudanças alheias no working tree. Fazer stage somente por paths
  explícitos e nunca commitar alterações de produto paralelas.
- Executar `mix quality` antes de cada commit. Se a base estiver vermelha por
  trabalho paralelo, rebasear depois que o commit-base estiver verde; não
  absorver a correção alheia nesta branch.

---

### Task 1: Ativar os checks e corrigir as specs existentes

**Files:**

- Create: `.credo.exs`
- Modify: `apps/leafcutter_core/lib/leafcutter_core.ex:6-17`
- Modify: `apps/leafcutter_runtime/lib/leafcutter_runtime.ex:6-17`
- Modify: `apps/leafcutter_runtime/test/support/resolution_fixtures.ex:4-220`
- Modify: `apps/leafcutter_api/lib/leafcutter_api.ex:20-55`
- Modify: `apps/leafcutter_api/lib/leafcutter_api/telemetry.ex:5-61`
- Modify: `apps/leafcutter_api/lib/leafcutter_api/controllers/error_json.ex:15-20`
- Test temporarily: `apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs`

**Interfaces:**

- Consumes: `mix credo --strict` já chamado pelo alias raiz; defaults do Credo
  1.7.19; tipos públicos dos schemas retornados por `ResolutionFixtures`.
- Produces: `.credo.exs` com os três opt-ins; `ResolutionFixtures.fixture/0`;
  specs para as 12 definições reportadas e 14 aridades públicas.

- [ ] **Step 1: Criar a fixture negativa temporária antes da configuração**

Criar o arquivo abaixo sem adicioná-lo ao Git:

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

- [ ] **Step 2: Provar que o estado atual não aplica os checks**

Run:

```bash
mix credo suggest \
  apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs \
  --strict --format json
```

Expected: exit status `0` e JSON exatamente sem issues:

```json
{
  "issues": []
}
```

- [ ] **Step 3: Gerar e limitar a configuração versionada**

Run:

```bash
mix credo.gen.config
```

Na lista `enabled`, adicionar os checks em suas categorias correspondentes:

```elixir
{Credo.Check.Design.SkipTestWithoutComment, []}
{Credo.Check.Readability.Specs, [include_defp: false]}
{Credo.Check.Warning.UnsafeToAtom, []}
```

Remover da lista `disabled` as três entradas geradas:

```elixir
{Credo.Check.Design.SkipTestWithoutComment, []}
{Credo.Check.Readability.Specs, []}
{Credo.Check.Warning.UnsafeToAtom, []}
```

Não mover ou editar outro check.

- [ ] **Step 4: Provar que a configuração detecta as três violações**

Run:

```bash
mix credo suggest \
  apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs \
  --strict --format json
```

Expected: exit status diferente de `0`, três issues e este conjunto exato no
campo `check`:

```text
Credo.Check.Design.SkipTestWithoutComment
Credo.Check.Readability.Specs
Credo.Check.Warning.UnsafeToAtom
```

- [ ] **Step 5: Remover a fixture negativa**

Remover somente:

```text
apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs
```

Confirmar:

```bash
test ! -e apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs
```

- [ ] **Step 6: Provar que a configuração encontra as ausências reais**

Run:

```bash
mix credo --strict --format json
```

Expected: exit status diferente de `0`, exatamente 12 issues, todas com:

```json
"check": "Credo.Check.Readability.Specs"
```

- [ ] **Step 7: Tipar a fixture de resolução**

Adicionar aliases de tipos sem substituir as facades já usadas:

```elixir
alias Leafcutter.Catalog.{Connector, Contract, ContractVersion, Operation, Package, PackageVersion}
alias Leafcutter.Connections.{Connection, Secret, SecretVersion}
alias Leafcutter.Integrations.{EnvironmentDeployment, Integration}
alias Leafcutter.Organizations.{Environment, Organization}
```

Adicionar a shape completa e as specs antes de `deployment_fixture/2`:

```elixir
@type fixture :: %{
        organization: Organization.t(),
        environment: Environment.t(),
        source_connector: Connector.t(),
        destination_connector: Connector.t(),
        contract: Contract.t(),
        package: Package.t(),
        package_version: PackageVersion.t(),
        integration: Integration.t(),
        deployment: EnvironmentDeployment.t(),
        source_operation: Operation.t(),
        destination_operation: Operation.t(),
        source_contract_version: ContractVersion.t(),
        warehouse_contract_version: ContractVersion.t(),
        crm_contract_version: ContractVersion.t(),
        source_secret: Secret.t(),
        source_secret_version: SecretVersion.t(),
        source_connection: Connection.t(),
        warehouse_connection: Connection.t(),
        crm_connection: Connection.t()
      }

@spec deployment_fixture() :: fixture()
@spec deployment_fixture(String.t()) :: fixture()
@spec deployment_fixture(String.t(), keyword()) :: fixture()
```

Adicionar antes de `delete_persisted_fixture/1`:

```elixir
@spec delete_persisted_fixture(fixture()) :: :ok
```

- [ ] **Step 8: Adicionar as specs da API e dos módulos raiz**

Em `LeafcutterApi.Telemetry`:

```elixir
@spec start_link(term()) :: Supervisor.on_start()
@spec metrics() :: [Telemetry.Metrics.t()]
```

Em `LeafcutterApi.ErrorJSON`:

```elixir
@spec render(String.t(), map()) :: %{errors: %{detail: String.t()}}
```

Em `LeafcutterApi`, associar cada spec à função correspondente:

```elixir
@spec static_paths() :: [String.t()]
@spec router() :: Macro.t()
@spec channel() :: Macro.t()
@spec controller() :: Macro.t()
@spec verified_routes() :: Macro.t()
```

Em `LeafcutterRuntime` e `LeafcutterCore`, respectivamente:

```elixir
@spec hello() :: :world
```

- [ ] **Step 9: Formatar os arquivos tocados**

Run:

```bash
mix format .credo.exs \
  apps/leafcutter_core/lib/leafcutter_core.ex \
  apps/leafcutter_runtime/lib/leafcutter_runtime.ex \
  apps/leafcutter_runtime/test/support/resolution_fixtures.ex \
  apps/leafcutter_api/lib/leafcutter_api.ex \
  apps/leafcutter_api/lib/leafcutter_api/telemetry.ex \
  apps/leafcutter_api/lib/leafcutter_api/controllers/error_json.ex
```

- [ ] **Step 10: Verificar o enforcement e os tipos**

Run:

```bash
mix credo --strict
mix compile --warnings-as-errors
mix dialyzer
test ! -e apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs
mix quality
```

Expected: todos os comandos saem com status `0`; Credo encontra zero issues;
Dialyzer reporta zero errors; todas as suítes terminam sem failures.

- [ ] **Step 11: Revisar o diff e commitar o gate executável**

Run:

```bash
git diff --check
git status --short
git diff -- .credo.exs \
  apps/leafcutter_core/lib/leafcutter_core.ex \
  apps/leafcutter_runtime/lib/leafcutter_runtime.ex \
  apps/leafcutter_runtime/test/support/resolution_fixtures.ex \
  apps/leafcutter_api/lib/leafcutter_api.ex \
  apps/leafcutter_api/lib/leafcutter_api/telemetry.ex \
  apps/leafcutter_api/lib/leafcutter_api/controllers/error_json.ex
```

Expected: nenhum arquivo temporário, nenhuma mudança de corpo e nenhum path
fora da lista desta task.

Commit:

```bash
git add .credo.exs \
  apps/leafcutter_core/lib/leafcutter_core.ex \
  apps/leafcutter_runtime/lib/leafcutter_runtime.ex \
  apps/leafcutter_runtime/test/support/resolution_fixtures.ex \
  apps/leafcutter_api/lib/leafcutter_api.ex \
  apps/leafcutter_api/lib/leafcutter_api/telemetry.ex \
  apps/leafcutter_api/lib/leafcutter_api/controllers/error_json.ex
git commit -m "chore: enforce Credo specs and safety checks"
```

---

### Task 2: Registrar a materialização da H1A

**Files:**

- Modify: `docs/implementation/quality-gates.md:24-32`
- Modify: `docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md:110-129`
- Modify: `docs/harness/specifications/H1A-credo-enforcement.md:1-175`

**Interfaces:**

- Consumes: `.credo.exs` e as specs materializadas pela Task 1; contrato
  documental canônico estabelecido por H0.
- Produces: descrição operacional dos checks, status H1A materializado e links
  para specification e plano; H1B a H1E permanecem pendentes.

- [ ] **Step 1: Documentar a etapa Credo no gate canônico**

Depois do parágrafo que termina em "checker objetivo", adicionar:

~~~~markdown
### Configuração do Credo

A etapa `mix credo --strict` carrega `.credo.exs`. Além dos checks padrão
fixados para o Credo 1.7.19, a configuração habilita somente estes checks
opt-in:

~~~text
Credo.Check.Design.SkipTestWithoutComment
Credo.Check.Readability.Specs com include_defp: false
Credo.Check.Warning.UnsafeToAtom
~~~

O check de specs cobre funções públicas. Checks controversos ou experimentais
adicionais exigem um incremento próprio com prova negativa.
~~~~

- [ ] **Step 2: Atualizar o status da specification**

Substituir o status inicial por:

```markdown
> **Status: MATERIALIZADO NA TRILHA ALTERNATIVA.** Esta specification detalha
> o subincremento H1A do harness. Ela não altera a sequência de produto nem
> `docs/checkpoint/CURRENT.md`.
```

Antes de `## Fora de escopo`, adicionar:

```markdown
## Evidência

- `.credo.exs` com os três checks opt-in;
- specs nos módulos listados nesta specification;
- prova negativa temporária executada antes da correção;
- `mix credo --strict` sem issues;
- `mix quality` com status `0`.

Plan: `docs/harness/plans/2026-08-30-h1a-credo-enforcement.md`.
```

- [ ] **Step 3: Marcar somente H1A como materializado no roadmap**

Fazer o item H1A declarar seu estado e apontar para os dois documentos:

```markdown
1. H1A, materializado, cria `.credo.exs`, corrige as ausências reais de specs e
   habilita somente `Credo.Check.Readability.Specs`,
   `Credo.Check.Warning.UnsafeToAtom` e
   `Credo.Check.Design.SkipTestWithoutComment`. Specification:
   `docs/harness/specifications/H1A-credo-enforcement.md`. Plan:
   `docs/harness/plans/2026-08-30-h1a-credo-enforcement.md`;
```

Não alterar os estados ou o texto de H1B a H1E.

- [ ] **Step 4: Verificar documentação e gate completo**

Run:

```bash
test -z "$(rg -n '[T]BD|implement[ ]later|fill[ ]in[ ]details' \
  docs/harness/specifications/H1A-credo-enforcement.md \
  docs/harness/plans/2026-08-30-h1a-credo-enforcement.md)"
test "$(rg -l 'Credo.Check.Readability.Specs' \
  docs/implementation/quality-gates.md \
  docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md \
  docs/harness/specifications/H1A-credo-enforcement.md | wc -l)" -eq 3
test ! -e apps/leafcutter_api/test/h1a_credo_negative_fixture_test.exs
git diff --check
mix quality
```

Expected: checks documentais com status `0`, nenhum whitespace error, arquivo
temporário ausente e `mix quality` verde.

- [ ] **Step 5: Revisar o escopo e commitar a materialização**

Run:

```bash
git status --short
git diff -- docs/implementation/quality-gates.md \
  docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md \
  docs/harness/specifications/H1A-credo-enforcement.md
git diff --quiet HEAD -- docs/checkpoint/CURRENT.md docs/decisions
```

Expected: somente os três documentos desta task mudam; H1B a H1E continuam
pendentes; checkpoint e ADRs permanecem intactos.

Commit:

```bash
git add docs/implementation/quality-gates.md \
  docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md \
  docs/harness/specifications/H1A-credo-enforcement.md
git commit -m "docs: mark H1A Credo enforcement materialized"
```
