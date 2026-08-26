# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Runtime ownership foundation**

A primeira foundation funcional de RBAC de `Organizations` está concluída para
`User` e `ServiceAccount`.

A infraestrutura OTP mínima de `leafcutter_runtime` está materializada e o
heartbeat por incarnação de runtime agora possui representação durável em
PostgreSQL.

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
- `leafcutter_runtime` supervisiona `LeafcutterRuntime.RunRegistry`,
  `LeafcutterRuntime.RunDynamicSupervisor` e `LeafcutterRuntime.NodeHeartbeat`;
- `leafcutter_api` é Phoenix API-only com Endpoint e Telemetry;
- `Organizations` possui schemas/migrations para `Organization`, `Environment`,
  `User`, `ServiceAccount`, `Membership`, `Role`, `RolePermission`, `RoleAssignment`
  e `ServiceAccountRoleAssignment`;
- `Permission` é primitive conhecida em código, sem tabela própria;
- `Organizations.Access` expõe membership, role assignment para usuários e `authorize/3`;
- `Organizations.Access.ServiceAccounts` expõe role assignment para service accounts;
- `Organizations.Roles` expõe grant/revoke de permissions;
- authorization usa actor tuples (`{:user, id}` / `{:service_account, id}`) e
  scope tuples (`{:organization, id}` / `{:environment, id}`), sem `Principal` persistido;
- assignments organization-wide satisfazem checks em Environment; assignments
  environment-scoped não satisfazem checks organization-wide nem outros Environments;
- `Executions` possui `RuntimeNode` e `Executions.Nodes.heartbeat/2` para liveness durável;
- `RuntimeNode.id` identifica uma incarnação específica da application runtime;
- `node_name` é metadata reutilizável e deliberadamente não possui unicidade;
- reiniciar apenas `NodeHeartbeat` preserva o `runtime_node_id`; reiniciar a
  application/BEAM gera outro identificador;
- `NodeHeartbeat` persiste liveness antes de emitir Telemetry e continua tentando
  após falhas temporárias de banco sem entrar em crash loop;
- testes usam SQL Sandbox e cobrem constraints, lifecycle, concorrência, RBAC,
  supervision e heartbeat durável já materializados;
- nenhum Run process, Run ownership claim, generation/fencing ou Broadway pipeline foi criado.

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
RuntimeNode
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

Migrations são centralizadas em:

```text
apps/leafcutter_core/priv/repo/migrations/
```

Isso inclui tabelas owned por `Executions` em `leafcutter_runtime`, como
`runtime_nodes`.

## Runtime baseline

Supervision tree materializada:

```text
LeafcutterRuntime.Application
├── LeafcutterRuntime.RunRegistry
├── LeafcutterRuntime.RunDynamicSupervisor
└── LeafcutterRuntime.NodeHeartbeat
```

`RunRegistry` é local e possui keys `:unique`.

`RunDynamicSupervisor` permanece vazio até existir ownership durável de Run.

`NodeHeartbeat` usa um UUID por incarnação e atualiza:

```text
runtime_nodes.last_heartbeat_at
```

A mesma application identity sobrevive a restart isolado do heartbeat. Uma nova
application identity é criada após restart da application ou do BEAM.

Runtime supervision conceitual futura por Run:

```text
Run Supervisor
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

Uma Run tree permanece em um único node inicialmente.

PostgreSQL é autoridade durável para liveness, ownership e fencing.

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

Organizations Organization + Environment Foundation
→ completed

Organizations User + Membership Foundation
→ completed

Organizations Role + Permission Foundation
→ completed

Organizations User RoleAssignment Foundation
→ completed

Organizations ServiceAccount Identity Foundation
→ completed

Organizations ServiceAccount RoleAssignment Foundation
→ completed

Organizations Authorization Evaluation Foundation
→ completed

Runtime OTP Supervision Foundation
→ completed

Durable Runtime Node Liveness Foundation
→ completed
```

## In progress

Preparar o modelo durável mínimo de Run ownership e fencing.

## Next concrete task

Ratificar e materializar o primeiro schema de `Run` com os campos mínimos necessários
para ownership:

```text
owner_node_id
→ runtime_nodes.id | nil

generation
→ monotonic fencing token
```

A próxima decisão deve fechar:

- estado mínimo de lifecycle de Run necessário para claim;
- timeout que torna um `RuntimeNode` expirado;
- operação atômica de claim/reclaim;
- incremento de `generation` durante cada nova posse;
- contrato usado para rejeitar escritas de stale owners;
- quando ownership pode ser liberado explicitamente.

Ainda não criar `RunSupervisor`, `RunCoordinator` ou Broadway antes dessa authority
durável existir.

## Open warnings

- Run schema, ownership claim e generation/fencing ainda não foram materializados;
- timeout de expiração de runtime node ainda não foi fechado;
- política de retenção/cleanup de incarnações antigas ainda não foi fechada;
- autenticação concreta/credenciais de `ServiceAccount` ainda não foram modeladas;
- AuditEvent para histórico de permission/role assignment ainda não foi materializado;
- mecanismo físico de inclusão de `packages/` no build ainda não foi ratificado;
- JSON Schema definitivo de `manifest.json` ainda não foi fechado;
- mecanismo físico de durable cross-context facts/outbox ainda não foi fechado;
- mecanismo concreto de historical deployment state ainda não foi fechado;
- cliente HTTP e pool strategy ainda não foram escolhidos;
- configuração concreta de Oban queues/plugins ainda não foi escolhida;
- endpoints, schemas, tabelas, campos e índices de outros contexts ainda não estão congelados.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/modelo-conceitual.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/ambientes-rbac-homologacao.md`
- `docs/architecture/observabilidade-e-auditoria.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`
- `docs/decisions/ADR-0004-estado-operacional-e-duravel.md`
- `docs/decisions/ADR-0011-run-ownership-fencing.md`
