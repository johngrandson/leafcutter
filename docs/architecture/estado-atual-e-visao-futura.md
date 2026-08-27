# Estado atual e visão futura

> **Status: CANÔNICO.** Este documento é a ponte entre o repositório executável e a arquitetura planejada. Ele não substitui os ADRs nem `CURRENT.md`.

## Como ler a arquitetura

O Leafcutter evolui por slices verticais. Por isso, três descrições coexistem:

```text
materialized now
→ comportamento existente e testado

ratified next
→ direção aprovada, ainda incompleta no código

open
→ decisão que não deve ser implementada por inferência
```

## Estado materializado

### OTP applications

```text
apps/
├── leafcutter_core
├── leafcutter_connectors
├── leafcutter_runtime
└── leafcutter_api
```

Grafo real:

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → leafcutter_core + leafcutter_connectors
leafcutter_api        → leafcutter_core + leafcutter_runtime
```

### Infraestrutura compartilhada

`leafcutter_core` supervisiona:

```text
Leafcutter.Repo
Leafcutter.PubSub
Oban
```

Existe um único Repo e uma única stream de migrations em `apps/leafcutter_core/priv/repo/migrations/`, inclusive para tabelas owned pelo context `Executions`.

### Organizations e RBAC

Estão materializados:

```text
Organization
Environment
User
ServiceAccount
Membership
Role
RolePermission
RoleAssignment
ServiceAccountRoleAssignment
```

Capacidades públicas incluem lifecycle básico, membership, role assignment, grant/revoke de permissions e autorização para:

```text
{:user, user_id}
{:service_account, service_account_id}
```

Scopes:

```text
{:organization, organization_id}
{:environment, environment_id}
```

Assignment organization-wide herda para Environments da mesma Organization. Assignment environment-scoped não herda para Organization nem para outro Environment.

### Runtime e Executions foundation

Persistência atual:

```text
RuntimeNode
Run
```

`RuntimeNode.id` identifica uma incarnação da application runtime. `node_name` é metadata reutilizável. O heartbeat usa o relógio do PostgreSQL.

`Run` possui:

```text
status
owner_node_id
generation
ownership_acquired_at
```

Estados atuais:

```text
pending
running
completed
failed
cancelled
```

Ownership é serializado no PostgreSQL. `generation` é o fencing token monotônico.

### Supervision e recovery atuais

```text
LeafcutterRuntime.Application
├── RunRegistry
├── RunDynamicSupervisor
├── NodeHeartbeat
└── RunRecovery
```

Árvore por Run:

```text
RunDynamicSupervisor
└── RunSupervisor <run_id>
    └── RunCoordinator
```

O Registry é local. PostgreSQL é a autoridade distribuída.

`RunRecovery`:

```text
polls every 5 seconds
→ reconstructs local trees already owned by this incarnation
→ claims unowned or stale-owned running Runs
→ FOR UPDATE SKIP LOCKED
→ starts local trees after commit
```

Runs `pending` ainda não entram no recovery automático.

### API atual

`leafcutter_api` é uma application Phoenix API-only com Endpoint, Router, Telemetry e error JSON básicos. Autenticação concreta, OpenAPI completo e endpoints de produto ainda não foram materializados.

### Connectors atuais

`leafcutter_connectors` existe como OTP application e boundary, mas ainda não possui behaviours, transports ou implementações executáveis de connector.

## Arquitetura ratificada ainda não materializada

### Catalog

Planejado e ratificado:

```text
Connector + ConnectorVersion
Operation metadata
Contract + ContractVersion
Package + PackageVersion
publication and availability metadata
```

Versões publicadas serão imutáveis.

### Connections

Planejado e ratificado:

```text
Connection
Secret
SecretVersion
OAuth durable state
rotation metadata
```

Raw secrets não entram em PackageVersion, RunSnapshot, logs, AuditEvent ou respostas de API.

### Integrations

Planejado e ratificado:

```text
Integration
EnvironmentDeployment
Triggers
HomologationRequest
Promotion history
IdentityMapping
```

Promotion copia somente estado promovível; não copia secrets, Connections, Triggers ou config local do target.

### Executions completo

Planejado:

```text
RunSnapshot
Record
Delivery
Attempt
Checkpoint
ExecutionEvent
Enrichment execution state
```

A próxima decisão é o `RunSnapshot` imutável e o workflow público de criação de Run.

### Data plane Broadway

Forma futura ratificada:

```text
RunSupervisor
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

Source persiste Records, Deliveries e Checkpoint atomicamente. Destination consome backlog durável do PostgreSQL com batching, retries e isolamento por destino.

### Connectors e contracts

Planejado:

```text
Connector
→ Operation
→ Transport

JSON Schema Draft 2020-12
→ JSV validation
```

HTTP é o primeiro Transport. Outras opções entram somente com demanda real.

### Notifications e Audit

Planejado:

```text
NotificationRule
Recipient
NotificationDelivery
AuditEvent
```

Audit é append-only. Notifications e Audit consomem fatos duráveis self-contained.

### Integration Packages

Estrutura ratificada:

```text
packages/<package>/
├── mix.exs
├── manifest.json
├── lib
└── test
```

A estratégia física para incluí-los na release continua aberta.

## Decisões abertas

Entre as principais:

- forma exata de `RunSnapshot`;
- workflow público de criação de Run;
- schemas de Catalog, Connections e Integrations;
- mecanismo físico de durable cross-context facts;
- histórico concreto de EnvironmentDeployment;
- Package Manifest JSON Schema v1;
- inclusão de `packages/*` no build;
- cliente HTTP e pool strategy;
- lifecycle completo de Run, pause/resume/cancel e terminalização;
- Record/Delivery/Attempt/Checkpoint e data plane Broadway;
- secret provider/encryption;
- retenção de RuntimeNodes, Runs e payloads;
- OpenAPI e autenticação concretos.

## Guardrails contra confusão

Não afirmar que uma capacidade futura já existe porque seu nome aparece em um diagrama.

Não remover uma capacidade futura ratificada apenas porque ainda não existe implementação.

Não criar schema, processo OTP ou abstraction para preencher diagramas. Cada elemento entra quando seu lifecycle, persistência ou contrato for necessário.

## Próxima fronteira

```text
validated executable definition
↓ transaction
Run + immutable RunSnapshot
↓
pending Run becomes safely startable
```

Somente depois disso o scanner poderá considerar Runs `pending` automaticamente sem interpretar uma linha mínima como uma execução completa.
