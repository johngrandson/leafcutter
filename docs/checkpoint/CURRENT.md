# Leafcutter — checkpoint atual

> Atualize este arquivo ao concluir um marco, ratificar uma decisão ou mudar a próxima tarefa. Para a distinção entre código atual e visão futura, leia `docs/architecture/estado-atual-e-visao-futura.md`.

## Fase atual

**RunSnapshot v1 materialization**

As foundations de tenancy/RBAC e do runtime control plane estão materializadas. O contrato de RunSnapshot v1 foi ratificado, mas ainda não existe no código ou no banco.

## Estado materializado

### Applications e infraestrutura

```text
apps/
├── leafcutter_core
├── leafcutter_connectors
├── leafcutter_runtime
└── leafcutter_api
```

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → core + connectors
leafcutter_api        → core + runtime
```

`leafcutter_core` supervisiona um Repo, PubSub e Oban compartilhados. Migrations são centralizadas em core.

### Organizations

Materializado:

```text
Organization
Environment
User
ServiceAccount
Membership
Role
Permission
RolePermission
RoleAssignment
ServiceAccountRoleAssignment
```

APIs cobrem lifecycle básico, membership, roles, grants e authorization para User/ServiceAccount em scope de Organization ou Environment.

Catálogo atual de permissions:

```text
organization.read
organization.manage
environment.read
environment.manage
access.manage
```

### Executions e runtime

Materializado:

```text
RuntimeNode
Run
Nodes.heartbeat/2
Runs.claim/2
Runs.release/1
Runs.list_owned_tokens/1
Runs.claim_recoverable/3
```

Run possui status mínimo, owner, generation e ownership timestamp. PostgreSQL é authority de liveness, ownership e fencing.

Supervision tree:

```text
LeafcutterRuntime.Application
├── RunRegistry
├── RunDynamicSupervisor
├── NodeHeartbeat
└── RunRecovery
```

Árvore local:

```text
RunSupervisor
└── RunCoordinator
```

`RunRecovery` reconstrói árvores já owned e reclama Runs `running` sem owner ou com owner expirado usando polling e `FOR UPDATE SKIP LOCKED`.

Runs `pending` ainda não são iniciadas automaticamente. RunSnapshot, criação pública de Run e eligibility por formato ainda não estão materializados.

### API e connectors

`leafcutter_api` possui Phoenix Endpoint/Router/Telemetry básicos. `leafcutter_connectors` existe como boundary, mas ainda não possui contracts executáveis.

## Arquitetura ratificada preservada

Ainda não materializados:

```text
Catalog
Connections
Integrations
Notifications
Audit
RunSnapshot v1
Record
Delivery
Attempt
Checkpoint
ExecutionEvent
Connector/Operation/Transport
JSON Schema + JSV
Integration Packages
Broadway data plane
OpenAPI completo
Homologation/Promotion/Rollback
```

Para RunSnapshot v1, o contrato físico, o formato da definition, a criação atômica e a eligibility de `pending` estão ratificados em ADR-0017 e na specification correspondente.

## Completed milestones

```text
Context Map ratification
OTP application materialization
Shared Repo + PubSub + Oban
Organizations lifecycle
User + Membership
Role + Permission
User RoleAssignment
ServiceAccount identity
ServiceAccount RoleAssignment
Authorization evaluation
Runtime OTP foundation
Durable RuntimeNode liveness
Run ownership + fencing
RunSupervisor + RunCoordinator
Automatic RunRecovery bootstrap
Documentation present/future alignment
RunSnapshot v1 contract ratification
```

## Em andamento

Materializar o contrato ratificado de RunSnapshot v1 sem antecipar Catalog, Connections ou Integrations.

## Próxima tarefa concreta

Implementar, nesta ordem lógica:

```text
run_snapshots persistence + immutable schema
↓
typed definition v1 validation
↓ transaction
Runs.create/1 → Run + RunSnapshot
↓
Runs.fetch_snapshot/1
↓
pending eligibility in claim and recovery
```

Fechar no código e nos testes:

- relação 1:1 por shared primary key;
- constraints, `ON DELETE CASCADE` e trigger que rejeita `UPDATE`;
- formato v1 e versões suportadas;
- criação pública atômica;
- leitura explícita do snapshot;
- novos erros de claim;
- recovery de `pending` com snapshot suportado;
- compatibilidade com Runs legadas `running` sem snapshot.

Ainda não adicionar resolver de EnvironmentDeployment, schemas upstream, Broadway ou Record/Delivery.

## Principais decisões abertas

- schemas/APIs de Catalog, Connections e Integrations;
- resolução semântica de EnvironmentDeployment para a definition v1;
- Package Manifest e build de packages;
- Connector/Operation/Transport contracts;
- data plane e durable fan-out;
- lifecycle completo de Run;
- autenticação e secrets;
- OpenAPI/error envelope;
- durable cross-context facts;
- infraestrutura/cluster de produção;
- retenção e storage tiers.

## Leitura relevante

- `docs/decisions/ADR-0017-run-snapshot-v1.md`
- `docs/specifications/run-snapshot-v1.md`
- `docs/architecture/estado-atual-e-visao-futura.md`
- `docs/architecture/modelo-conceitual.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/durabilidade-e-recovery.md`
- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/decisoes-em-aberto.md`
- `docs/specifications/run-ownership.md`
- `docs/decisions/ADR-0011-run-ownership-fencing.md`
- `docs/decisions/ADR-0016-documentacao-presente-e-futuro.md`
