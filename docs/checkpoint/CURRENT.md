# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**First vertical domain slice - Organizations foundation**

A infraestrutura compartilhada mínima de `leafcutter_core` foi materializada.

O primeiro recorte de domínio de `Organizations` está em andamento com
`Organization` e `Environment` persistidos.

## Repository state

A umbrella contém quatro OTP applications materializadas:

```text
apps/
├── leafcutter_core/
├── leafcutter_connectors/
├── leafcutter_runtime/
└── leafcutter_api/
```

Estado atual:

- `leafcutter_core` supervisiona `Leafcutter.Repo`, `Leafcutter.PubSub` e Oban;
- `leafcutter_connectors` possui supervision tree vazia;
- `leafcutter_runtime` possui supervision tree vazia;
- `leafcutter_api` é Phoenix API-only com Endpoint e Telemetry;
- `Organizations` possui schemas e migrations para `Organization` e `Environment`;
- `Organizations` expõe create/get/disable para organizations e create/get para environments;
- testes de integração usam SQL Sandbox e cobrem constraints e concorrência entre
  disable de organization e criação de environment;
- nenhum Run process, Broadway pipeline ou Registry foi criado.

## Ratified Context Map

Contexts:

```text
Organizations
Catalog
Connections
Integrations
Executions
Notifications
Audit
```

Após a revisão conjunta, todos possuem zero dependências diretas de domínio entre si:

```text
Organizations   → none
Catalog         → none
Connections     → none
Integrations    → none
Executions      → none
Notifications   → none
Audit           → none
```

Cross-context use cases são compostos por application workflow modules na OTP application que possui o use case.

Uma referência por ID não cria dependência de API entre contexts.

## Context ownership consolidado

### Organizations

Owns:

```text
Organization
Environment
User
ServiceAccount
Membership
Role
Permission
access grants / assignments
```

Autorização é aplicada na application/API boundary.

### Catalog

Owns:

```text
Connector metadata
ConnectorVersion
Operation metadata
Contract
ContractVersion
Package
PackageVersion
publication / availability metadata
```

Ratificações importantes:

- `Operation` pertence a `ConnectorVersion`; não existe `OperationVersion` inicialmente;
- published `PackageVersion`, `ConnectorVersion` e `ContractVersion` são imutáveis;
- `PackageDependency` removido do V1;
- categorias são metadata, não entidade;
- PackageVersion topológica inicial: exatamente 1 Source -> 1..N Destinations.

### Connections

Owns:

```text
Connection
Secret
SecretVersion
auth configuration
OAuth token / refresh durable state
rotation metadata
```

`Connection` referencia Connector identity, não ConnectorVersion.

### Integrations

`Integration` é identidade lógica dentro de uma Organization e possui Package estável.

A configuração executável environment-specific pertence a:

```text
EnvironmentDeployment
```

Existe um deployment lógico corrente por `Integration + Environment`.

Ratificações importantes:

- EnvironmentDeployment seleciona PackageVersion;
- source/destination Connection bindings são environment-local;
- Triggers são environment-local;
- promotable config é separado de environment-local config;
- HomologationRequest aprova state fingerprint específico;
- Promotion não copia secrets, connections ou triggers;
- Rollback é operação, não entidade inicial;
- IdentityMapping pertence a Integrations e é scoped por EnvironmentDeployment + Destination.

### Executions

Owns:

```text
Run
RunSnapshot
Record
Delivery
Attempt
Enrichment execution result/status
Checkpoint
ExecutionEvent
durable ownership/fencing/recovery state
```

Runtime OTP infrastructure não pertence ao Context ownership.

### Notifications

Owns:

```text
NotificationRule
Recipient
NotificationDelivery
```

`NotificationChannel` e `NotificationAttempt` não são entidades iniciais.

### Audit

Owns `AuditEvent`, que é append-only e imutável.

Audit é sink e não participa de decisões de negócio de outros contexts.

## Cross-context durable facts

Notifications e Audit consomem fatos duráveis self-contained.

Quando a emissão do fato é obrigação do sistema, ele deve ser persistido atomicamente com a mudança de domínio que o originou.

Não criar um Context `Events` ou `Outbox`.

A implementação física do mecanismo ainda está aberta.

`ExecutionEvent` continua restrito ao lifecycle de execução e não é event bus genérico.

## Ratified OTP application boundaries

### `leafcutter_core`

Hosts:

```text
Organizations
Catalog
Connections
Integrations
Notifications
Audit
Leafcutter.Repo
Leafcutter.PubSub
Oban
```

### `leafcutter_connectors`

Hosts:

```text
Connector behaviours
Operation behaviours
Transport behaviours
HTTP Transport
Generic HTTP connector
connector implementations
shared transport infrastructure when needed
```

### `leafcutter_runtime`

Hosts:

```text
Executions
runtime application workflows
Registry
Run DynamicSupervisor
NodeHeartbeat
per-Run supervision trees
Broadway data plane
```

### `leafcutter_api`

Hosts:

```text
Phoenix Endpoint
controllers / plugs
API authentication
authorization boundary
OpenAPI
health / readiness
future inbound HTTP endpoints
```

## Ratified app dependency graph

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → leafcutter_core + leafcutter_connectors
leafcutter_api        → leafcutter_core + leafcutter_runtime
```

Esse grafo já está materializado nos `mix.exs`.

## Shared infrastructure decisions

Ratificado:

```text
one Leafcutter.Repo
→ leafcutter_core

one Leafcutter.PubSub
→ leafcutter_core

one Oban infrastructure
→ leafcutter_core
```

Migrations serão centralizadas em:

```text
apps/leafcutter_core/priv/repo/migrations/
```

Mesmo tabelas owned por `Executions` usarão essa migration stream compartilhada.

## Runtime baseline

Runtime supervision conceitual:

```text
LeafcutterRuntime.Application
├── Registry
├── Run DynamicSupervisor
└── NodeHeartbeat
```

Cada Run:

```text
Run Supervisor
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

Uma Run tree permanece em um único node inicialmente.

PostgreSQL é autoridade durável para ownership/fencing.

Sem `:global`, Horde ou fila externa inicialmente.

## Data-plane baseline

```text
SourceBroadway
→ fetch/decode/validate
→ Record + N Delivery intents
→ persist durable fan-out + checkpoint atomically

DestinationBroadway
→ claim pending Deliveries from PostgreSQL
→ transform
→ validate
→ batch
→ Connector/Operation/Transport
→ persist Delivery + Attempt outcome
```

`Delivery` é a representação durável do trabalho.

Não usar Oban ou external queue por Delivery inicialmente.

Semântica base: at-least-once.

## Integration Packages

Ratificado:

```text
packages/<package>/
├── mix.exs
├── manifest.json
├── lib/
└── test/
```

Cada Package é um Mix project independente fora de `apps/`.

Packages instalados serão compilados na mesma release inicial.

O mecanismo físico para incluí-los no build ainda está aberto.

## Release

Uma única release inicial:

```text
:leafcutter
```

Todos os nodes executam a mesma release completa inicialmente:

```text
core + connectors + runtime + api + installed packages
```

Sem classes especializadas de node no V1.

## Completed milestones

```text
Individual Context Ratification
→ completed

Full Context Map Review
→ completed

OTP Application Boundary Ratification
→ completed

OTP Application Materialization
→ completed

Application Dependency Graph
→ completed

Initial Release Shape
→ completed

Shared Repo + PubSub + Oban Foundation
→ completed

Organizations Organization Foundation
→ completed
```

## In progress

Completar o lifecycle inicial de `Environment` no Context `Organizations`.

## Next concrete task

Adicionar a operação pública idempotente:

```text
Organizations.Environments.disable/1
```

Ela deve preservar o timestamp original em chamadas repetidas e retornar erro
nomeado quando o environment não existir.

Após fechar o recorte inicial de `Organizations`:

```text
runtime OTP foundation
→ next ratified domain slice
```

Cada mudança deve permanecer pequena e revisável em PR própria quando fizer sentido.

## Open warnings

- mecanismo físico de inclusão de `packages/` no build ainda não foi ratificado;
- JSON Schema definitivo de `manifest.json` ainda não foi fechado;
- mecanismo físico de durable cross-context facts/outbox ainda não foi fechado;
- mecanismo concreto de historical deployment state ainda não foi fechado;
- cliente HTTP e pool strategy ainda não foram escolhidos;
- configuração concreta de Oban queues/plugins ainda não foi escolhida;
- endpoints, schemas, tabelas, campos e índices de domínio ainda não estão congelados.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/modelo-conceitual.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/ambientes-rbac-homologacao.md`
- `docs/architecture/observabilidade-e-auditoria.md`
