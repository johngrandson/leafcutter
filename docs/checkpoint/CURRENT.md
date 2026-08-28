# Leafcutter — checkpoint atual

> Atualize este arquivo ao concluir um marco, ratificar uma decisão ou mudar a próxima tarefa. Para a distinção entre código atual e visão futura, leia `docs/architecture/estado-atual-e-visao-futura.md`.

## Fase atual

**Upstream authority materialization**

As foundations de tenancy/RBAC e do runtime control plane estão materializadas. RunSnapshot v1 foi integrado à `main` pela PR #16. As authorities upstream mínimas e o workflow `EnvironmentDeployment → definition v1` foram ratificados no ADR-0018. Catalog, Connections, Integration, EnvironmentDeployment e seus bindings estão materializados nesta branch; o resolver permanece pendente.

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

### Catalog

Materializado:

```text
Connector
└── ConnectorVersion
    └── Operation

Contract
└── ContractVersion

Package
└── PackageVersion
    └── PackageVersionEndpoint

Catalog.Connectors.create/1
Catalog.Connectors.get/1
Catalog.Connectors.publish_version/2
Catalog.Contracts.create/1
Catalog.Contracts.get/1
Catalog.Contracts.publish_version/2
Catalog.Packages.create/1
Catalog.Packages.get/1
Catalog.Packages.publish_version/2
Catalog.Packages.get_version/1
```

ConnectorVersion e suas Operations são publicadas atomicamente. Um estado interno não publicado existe somente dentro da transação; constraint e mutation triggers impedem commit sem sealing, append tardio, update e delete. ContractVersion materializa somente identidade, nasce publicada e é imutável no PostgreSQL. PackageVersion publica uma source e uma ou mais destinations ordenadas; constraints e triggers protegem cardinalidade, compatibilidade de Operation role, referências, sealing e imutabilidade. Names, versions e refs rejeitam UTF-8 inválido antes da persistência.

### Connections

Materializado:

```text
Environment
├── Connection
│   └── optional exact SecretVersion binding
└── Secret
    └── immutable SecretVersion

Connections.create/1
Connections.get/1
Connections.update/2
Connections.disable/1
Connections.lock_active/3
Connections.Secrets.create/1
Connections.Secrets.create_version/1
Connections.Secrets.fetch_versions/3
```

Connection referencia Connector estável, guarda config JSON object não sensível e pode selecionar uma SecretVersion exata do mesmo Organization/Environment. Writes validam parents ativos sob locks compartilhados na ordem Organization → Environment; updates e disable lockam a Connection depois. `lock_active/3` oferece leitura bloqueada, única e ordenada por ID para workflows compostos. `Secrets.fetch_versions/3` retorna identities imutáveis exatas, únicas e ordenadas após validar o scope. FKs compostas, constraint de JSON object e trigger de binding protegem integridade no PostgreSQL. SecretVersion é única dentro de Secret e rejeita update/delete. Nenhum raw secret, ciphertext, provider locator ou credential é persistido.

### Integrations

Materializado:

```text
Organization
└── Integration
    └── EnvironmentDeployment
        └── EnvironmentDeploymentBinding

Integrations.create/1
Integrations.get/1
Integrations.disable/1
Integrations.lock_active/2
Integrations.Deployments.create/1
Integrations.Deployments.get/1
Integrations.Deployments.replace/2
Integrations.Deployments.lock_for_resolution/1
```

Integration referencia uma Package estável e torna Organization, Package e identidade imutáveis. Create valida a Organization ativa sob lock compartilhado; disable preserva um único timestamp sob locks na ordem Organization → Integration.

EnvironmentDeployment guarda PackageVersion, promotable/local config como JSON objects e o conjunto completo de bindings por endpoint. Create e replace validam Organization, Environment, Integration e Connections ativos sob locks determinísticos, além de PackageVersion, cobertura de refs e compatibilidade de Connector. `lock_for_resolution/1` protege deployment e bindings com shared locks dentro da transação do caller. Persistência e substituição são atômicas; constraints e triggers protegem identidade imutável, unicidade por Integration/Environment, config, cobertura e compatibilidade no PostgreSQL.

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

Run possui status mínimo, owner, generation e ownership timestamp. RunSnapshot congela a definition executável estruturalmente validada e versionada. A validação rejeita strings que não sejam UTF-8 antes da serialização JSONB. PostgreSQL é authority de liveness, ownership, fencing e imutabilidade persistida do snapshot.

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
Upstream authorities and deployment resolution contract ratification
Catalog Connector authority materialization
Catalog Contract authority materialization
Catalog Package topology materialization
Connections + SecretVersion binding materialization
Integration identity materialization
EnvironmentDeployment + binding materialization
Resolver-facing authority read APIs
```

## Em andamento

Materializar o resolver transacional de EnvironmentDeployment ratificado no ADR-0018.

## Próxima tarefa concreta

Implementar o próximo sub-slice em `leafcutter_runtime`:

```text
LeafcutterRuntime.Runs.create_from_deployment/1
→ uma transação compartilhada
→ locks via APIs públicas na ordem ratificada
→ revalidação semântica das authorities
→ deep merge de promotable_config + local_config
→ definition v1 congelando Connection config e SecretVersion ID
→ Executions.Runs.create/1
```

O resolver deve ordenar destinations pela posição do PackageVersionEndpoint e fazer rollback integral em qualquer falha. Duas chamadas bem-sucedidas continuam criando Runs distintas.

Não implementar ainda revision/history, promotion/rollback, triggers, raw secrets, provider locators, OAuth, rotation/revocation, actor, invocation, idempotency, carregamento no coordinator ou data plane.

## Principais decisões abertas

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

- `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`
- `docs/specifications/environment-deployment-run-resolution.md`
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
