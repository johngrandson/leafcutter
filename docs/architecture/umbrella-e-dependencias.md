# Umbrella e dependências

> **Status: MATERIALIZADO ATÉ 26C1; 26C2 PARCIAL — PASSOS 35–37.**

## Estrutura real

```text
apps/
├── leafcutter_core
├── leafcutter_connectors
├── leafcutter_runtime
└── leafcutter_api
```

Grafo materializado entre applications Leafcutter:

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → leafcutter_core + leafcutter_connectors + installed packages
leafcutter_api        → leafcutter_core + leafcutter_runtime
```

Não existe ciclo e nenhum context recebe OTP application própria.

O ramo adicional é materializado somente quando `packages/build.exs` contém uma entry:

```text
leafcutter_runtime → installed packages → leafcutter_connectors
```

A inventory de produção atual é vazia. A fixture de conformance é uma dependency exclusiva de
test e não integra o grafo ou a release de produção.

## `leafcutter_core`

Hospeda hoje:

```text
Organizations
Catalog
Connections
Integrations
Leafcutter.Repo
Leafcutter.PubSub
Oban
```

Hospedará futuramente:

```text
Notifications
Audit
```

Existe um único Repo, PubSub e Oban compartilhados.

Migrations são centralizadas em:

```text
apps/leafcutter_core/priv/repo/migrations
```

Isso inclui `runtime_nodes` e `runs`, embora seu ownership pertença a Executions.

## `leafcutter_connectors`

Boundary executável materializada para Operation, Transport HTTP e Package Manifest/binding.

Hospeda hoje:

```text
Operation Read/Write behaviours and values
bounded HTTP Transport facade
Finch HTTP/1 adapter and supervised pool
Package Manifest v1 validation and compiled bindings
```

Hospedará futuramente outros transports e connector implementations conforme demanda real.

Metadata e versionamento pertencem a Catalog; execução pertence a esta app.

## `leafcutter_runtime`

Hospeda hoje:

```text
Executions foundation
EnvironmentDeployment → RunSnapshot resolution
RunRegistry
RunDynamicSupervisor
NodeHeartbeat
RunRecovery
RunSupervisor
RunCoordinator
runtime workflows
```

Supervision tree atual:

```text
LeafcutterRuntime.Application
├── RunRegistry
├── RunDynamicSupervisor
├── NodeHeartbeat
└── RunRecovery
```

Hospedará o data plane futuro:

```text
SourceBroadway
optional EnrichmentBroadway
DestinationBroadway x N
```

## `leafcutter_api`

Materializado:

```text
Phoenix Endpoint
Router
Telemetry
basic error JSON
```

Futuro ratificado:

```text
authentication
RBAC boundary integration
controllers and plugs
canonical OpenAPI
health/readiness
inbound endpoints later
```

A app API não contém regra de negócio.

## Release

Uma release homogênea inicial está materializada:

```text
:leafcutter
```

Todos os nodes executarão core, connectors, runtime e api. Especialização de nodes só entra após necessidade medida.

A configuração Mix da umbrella materializa `:leafcutter` com `leafcutter_api` como entrypoint.
Core, Connectors, Runtime e os packages instalados entram pela dependency/application closure;
o gate compara os apps da inventory com a closure produzida por `Mix.Release`.

## Integration Packages

Localização ratificada:

```text
packages/
├── build.exs
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib
    └── test
```

Packages não são uma quinta platform application. O ADR-0023 ratifica inventory literal em
`packages/build.exs`, path dependencies explícitas de `leafcutter_runtime` e prova da
application closure da release. Essa estratégia está materializada no passo 37; module
resolution permanece no passo 38.

## Dependências permitidas

Package pode depender de contracts públicos de `leafcutter_connectors` e de dependencies Mix
próprias. No contract v1, não depende de Core, Runtime ou API.

## Pontos futuros preservados

- resolução do package instalado pela projeção do Catalog;
- uma única release inicialmente;
- possibilidade futura de especialização de nodes;
- object storage, package isolation e analytics apenas após necessidade;
- configuração concreta de Oban e tuning futuro dos HTTP pools ainda abertos.
