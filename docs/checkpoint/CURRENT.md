# Leafcutter — checkpoint atual

> Atualize este arquivo ao concluir um marco, ratificar uma decisão ou mudar a próxima tarefa. Para a distinção entre código atual e visão futura, leia `docs/architecture/estado-atual-e-visao-futura.md`.

## Fase atual

**Slice 26B materializado — contrato executável de Operation**

As foundations de tenancy/RBAC, runtime control plane e o workflow `EnvironmentDeployment → RunSnapshot v1` estão materializados na `main`. O Slice 26A está completo conforme o ADR-0019. O Slice 26B também está materializado conforme o ADR-0021: behaviours síncronos de Read/Write, invocation/result structs, cursor JSON opaco, partial success completo e ordenado, `Operation.Error`, redaction de credentials e invariantes puras. RunSnapshot v1 permanece inalterado.

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
Catalog.Contracts.compile/1
Catalog.Contracts.validate/2
Catalog.Packages.create/1
Catalog.Packages.get/1
Catalog.Packages.publish_version/2
Catalog.Packages.get_version/1
```

ConnectorVersion e suas Operations são publicadas atomicamente. Um estado interno não publicado existe somente dentro da transação; constraint e mutation triggers impedem commit sem sealing, append tardio, update e delete. A boundary pública de ContractVersion exige `version` e `schema`, faz cast por `SchemaDocument` e conclui a política pura e o build JSV antes do insert. O modelo físico mantém `schema :jsonb` nullable para preservar rows identity-only legadas, mas um CHECK rejeita raízes diferentes de object/boolean/SQL NULL e uma trigger `BEFORE INSERT` rejeita novos SQL NULL. A trigger existente de update/delete também protege o schema publicado. `Contracts.compile/1` distingue ausência e legado, reaplica a política, constrói no máximo uma root por chamada e retorna um validator Leafcutter opaco sem cache compartilhado. `Contracts.validate/2` rejeita termos não JSON antes do JSV, desabilita casts, reutiliza a root compilada e devolve o payload original ou um erro Leafcutter com paths e kinds ordenados, somente values JSON e sem messages dependentes do payload. PackageVersion publica uma source e uma ou mais destinations ordenadas; antes de inserir cada endpoint, a boundary confirma que sua ContractVersion possui schema persistido e faz rollback integral com erro em `contract_version_id` para versões legadas. PackageVersions históricas com legado permanecem legíveis. Constraints e triggers continuam protegendo cardinalidade, compatibilidade de Operation role, referências, sealing e imutabilidade. Names, versions e refs rejeitam UTF-8 inválido antes da persistência.

A rejeição de versões legadas em novas PackageVersions, novos Deployments e novas Runs resolvidas está materializada. PackageVersions, Deployments, Runs e RunSnapshots históricos permanecem legíveis sem reescrita.

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
Integrations.Deployments.fetch_resolution_scope/1
Integrations.Deployments.lock_for_resolution/1
```

Integration referencia uma Package estável e torna Organization, Package e identidade imutáveis. Create valida a Organization ativa sob lock compartilhado; disable preserva um único timestamp sob locks na ordem Organization → Integration.

EnvironmentDeployment guarda PackageVersion, promotable/local config como JSON objects e o conjunto completo de bindings por endpoint. Create e replace validam Organization, Environment, Integration e Connections ativos sob locks determinísticos, além de PackageVersion, cobertura de refs, compatibilidade de Connector e executabilidade de todas as ContractVersions projetadas. Versões legadas produzem IDs únicos e ordenados antes de qualquer persistência; Deployments históricos com legado permanecem legíveis. `fetch_resolution_scope/1` descobre somente os parent IDs imutáveis sem ler bindings; `lock_for_resolution/1` protege deployment e bindings com shared locks dentro da transação do caller. Persistência e substituição são atômicas; constraints e triggers protegem identidade imutável, unicidade por Integration/Environment, config, cobertura e compatibilidade no PostgreSQL.

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
LeafcutterRuntime.Runs.create_from_deployment/1
```

Run possui status mínimo, owner, generation e ownership timestamp. RunSnapshot congela a definition executável estruturalmente validada e versionada. `create_from_deployment/1` resolve authorities por APIs públicas dentro de uma única transação, revalida a executabilidade de todas as ContractVersions projetadas, calcula effective config, preserva destination order e congela Connection config e SecretVersion ID antes de criar a Run `pending`. Versões legadas produzem erro envelopado com IDs únicos e ordenados sem persistir Run ou RunSnapshot. A validação rejeita strings que não sejam UTF-8 antes da serialização JSONB. PostgreSQL é authority de liveness, ownership, fencing e imutabilidade persistida do snapshot.

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

`leafcutter_api` possui Phoenix Endpoint/Router/Telemetry básicos. `leafcutter_connectors` é uma library sem processo próprio e materializa a boundary executável de Operation. Ela não depende de Core, Ecto, Repo ou HTTP.

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
Transport executável e referência HTTP
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
Resolver scope discovery without binding reads
EnvironmentDeployment transactional resolver
Executable ContractVersion/JSV contract ratification
ContractVersion schema document representation and policy
ContractVersion internal JSV build boundary
ContractVersion nullable schema persistence
ContractVersion schema-aware publication and insert sealing
ContractVersion public compilation and opaque validator
ContractVersion public payload validation and safe errors
PackageVersion executable ContractVersion enforcement
EnvironmentDeployment executable ContractVersion enforcement
Run resolution executable ContractVersion enforcement
Executable Operation contract ratification
Executable Operation boundary materialization
Local derived knowledge base governance
Local knowledge schema and Claude adapters
Knowledge lint in mix quality
```

## Em andamento

Os Slices 26A e 26B estão integralmente materializados, e RunSnapshot v1 permanece
inalterado. A boundary de Operation é somente in-memory: não resolve módulos, não chama
Contracts, não executa Transport e não participa do RunCoordinator.

A próxima fronteira é ratificar o contract do Slice 26C antes de escrever Transport ou a
primeira referência HTTP.

## Próxima tarefa concreta

Ratificar o Slice 26C, fechando somente as decisões necessárias para um primeiro caminho HTTP:

~~~text
Transport ownership and callback boundary
→ request/response values
→ first reference Operation
→ operation_id-to-module resolution boundary
→ timeout/status/rate-limit/vendor-error translation
→ HTTP client and pool strategy
~~~

A ratificação precisa preservar a independência de `leafcutter_connectors` em relação a
Catalog/Repo, manter credentials efêmeras e separar HTTP do RunCoordinator e do data plane.
Nenhum código de Transport deve ser criado antes do novo ADR ser aceito.

Package Manifest completo, persisted Attempt/Delivery errors, backoff, idempotency, payload
limits, durable fan-out e Broadway continuam fora desse incremento.

## Principais decisões abertas

- Package Manifest e build de packages;
- resolução de `operation_id` via Package Manifest/build;
- Transport executável e referência HTTP (Slice 26C);
- data plane e durable fan-out;
- lifecycle completo de Run;
- autenticação e secrets;
- OpenAPI/error envelope;
- durable cross-context facts;
- infraestrutura/cluster de produção;
- retenção e storage tiers.

## Leitura relevante

- `docs/decisions/ADR-0021-operation-executavel.md`
- `docs/specifications/operation-contract.md`
- `docs/decisions/ADR-0008-connector-operation-transport.md`
- `docs/architecture/connectors-operations-transports.md`
- `docs/specifications/error-retry-model.md`
- `docs/decisions/ADR-0009-at-least-once.md`
- `docs/decisions/ADR-0005-broadway-como-data-plane.md`
- `docs/decisions/ADR-0010-fanout-duravel-sem-fila-externa.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/transformations-enrichments-interceptors.md`
- `docs/architecture/estado-atual-e-visao-futura.md`
- `docs/architecture/decisoes-em-aberto.md`
- `docs/decisions/ADR-0019-contract-version-executavel-json-schema-jsv.md`
- `docs/specifications/contract-version-execution.md`
