# Umbrella e dependências

> **Status: MATERIALIZADO, COM EVOLUÇÕES FUTURAS PRESERVADAS.**

## Estrutura real

```text
apps/
├── leafcutter_core
├── leafcutter_connectors
├── leafcutter_runtime
└── leafcutter_api
```

Grafo materializado:

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → leafcutter_core + leafcutter_connectors
leafcutter_api        → leafcutter_core + leafcutter_runtime
```

Não existe ciclo e nenhum context recebe OTP application própria.

## `leafcutter_core`

Hospeda hoje:

```text
Organizations
Catalog
Connections
Leafcutter.Repo
Leafcutter.PubSub
Oban
```

Hospedará futuramente:

```text
Integrations
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

Boundary materializada, ainda sem implementação funcional.

Hospedará:

```text
Connector behaviours
Operation behaviours
Transport behaviours
HTTP Transport
Generic HTTP Connector
connector implementations
```

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

Uma release homogênea inicial continua ratificada:

```text
:leafcutter
```

Todos os nodes executarão core, connectors, runtime e api. Especialização de nodes só entra após necessidade medida.

## Integration Packages

Localização ratificada:

```text
packages/<package>/
├── mix.exs
├── manifest.json
├── lib
└── test
```

Packages não são uma quinta platform application. A estratégia física de inclusão no build/release ainda está aberta.

## Dependências permitidas

Package pode depender de contracts públicos de `leafcutter_connectors`. Não depende de internals de runtime ou API. Dependência de core somente entra com contract público concreto.

## Pontos futuros preservados

- build explícito dos packages instalados;
- uma única release inicialmente;
- possibilidade futura de especialização de nodes;
- object storage, package isolation e analytics apenas após necessidade;
- configuração concreta de Oban e HTTP pools ainda aberta.
