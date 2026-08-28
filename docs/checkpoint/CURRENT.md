# Leafcutter — checkpoint atual

> Atualize este arquivo ao concluir um marco, ratificar uma decisão ou mudar a próxima tarefa. Para a distinção entre código atual e visão futura, leia `docs/architecture/estado-atual-e-visao-futura.md`.

## Fase atual

**RunSnapshot v1 materialization closure**

As foundations de tenancy/RBAC e do runtime control plane estão materializadas. RunSnapshot v1 também está materializado na feature branch, com fechamento condicionado à suíte integral e ao merge.

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
RunSnapshot
RunSnapshot.DefinitionV1
Nodes.heartbeat/2
Runs.create/1
Runs.fetch_snapshot/1
Runs.claim/2
Runs.release/1
Runs.list_owned_tokens/1
Runs.claim_recoverable/3
```

Run possui status mínimo, owner, generation e ownership timestamp. RunSnapshot congela a definition executável estruturalmente validada e versionada. PostgreSQL é authority de liveness, ownership, fencing e imutabilidade persistida do snapshot.

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

`RunRecovery` reconstrói árvores já owned, reclama Runs `running` sem owner ou com owner expirado e inicia Runs `pending` com snapshot suportado usando polling e `FOR UPDATE SKIP LOCKED`.

Runs `pending` sem snapshot ou com formato desconhecido permanecem inelegíveis. Runs legadas `running` preservam recovery independentemente de snapshot.

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

RunSnapshot v1 materializa o contrato físico, o formato da definition, a criação atômica, a leitura explícita e a eligibility de `pending` ratificados em ADR-0017 e na specification correspondente.

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
RunSnapshot v1 materialization
```

## Em andamento

Validar a suíte integral, revisar o diff final e preparar o merge da feature branch de RunSnapshot v1.

## Próxima tarefa concreta

Após fechar e integrar este slice, ratificar o menor slice upstream necessário para resolver uma definition v1 a partir de um `EnvironmentDeployment` persistido:

```text
Catalog authorities mínimas
+ Connections e SecretVersion bindings mínimos
+ Integration e EnvironmentDeployment persistidos
↓
resolver na orchestration de leafcutter_runtime
↓
definition v1 resolvida
↓
Executions.Runs.create/1
```

A próxima fase deve definir ownership, schemas e APIs mínimas desses contexts antes de implementar `create_from_deployment/1`. Não carregar o snapshot no RunCoordinator nem antecipar Broadway, Record ou Delivery.

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
