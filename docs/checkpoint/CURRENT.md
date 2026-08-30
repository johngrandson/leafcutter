# Leafcutter — checkpoint atual

> Atualize este arquivo ao concluir um marco, ratificar uma decisão ou mudar a próxima tarefa. Para a distinção entre código atual e visão futura, leia `docs/architecture/estado-atual-e-visao-futura.md`.

## Fase atual

**Slice 26C2 materializado — resolução compilada fechada**

As foundations de tenancy/RBAC, runtime control plane e o workflow `EnvironmentDeployment → RunSnapshot v1` estão materializados no código versionado por este checkpoint. Os Slices 26A, 26B, 26C1 e 26C2 estão completos conforme os ADRs 0019, 0021, 0022 e 0023. Os passos 35–38 de 26C2 materializam Manifest v1 bounded, digest dos bytes exatos, binding compilada, persistência imutável/globalmente única em PackageVersion, inventory literal ligada ao dependency graph/release e resolução por digest combinada com os IDs autoritativos do Catalog. Nenhum fluxo real completo de 26C3 foi materializado e RunSnapshot v1 permanece inalterado.

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
leafcutter_runtime    → core + connectors + installed packages
leafcutter_api        → core + runtime
```

`leafcutter_core` supervisiona um Repo, PubSub e Oban compartilhados. Migrations são centralizadas em core.
`leafcutter_runtime` deriva installed packages somente das entries literais de
`packages/build.exs`; a inventory de produção atual é vazia. A release homogênea
`:leafcutter` parte de `leafcutter_api` e inclui a closure transitiva desse grafo.

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

ConnectorVersion e suas Operations são publicadas atomicamente. Um estado interno não publicado existe somente dentro da transação; constraint e mutation triggers impedem commit sem sealing, append tardio, update e delete. A boundary pública de ContractVersion exige `version` e `schema`, faz cast por `SchemaDocument` e conclui a política pura e o build JSV antes do insert. O modelo físico mantém `schema :jsonb` nullable para preservar rows identity-only legadas, mas um CHECK rejeita raízes diferentes de object/boolean/SQL NULL e uma trigger `BEFORE INSERT` rejeita novos SQL NULL. A trigger existente de update/delete também protege o schema publicado. `Contracts.compile/1` distingue ausência e legado, reaplica a política, constrói no máximo uma root por chamada e retorna um validator Leafcutter opaco sem cache compartilhado. `Contracts.validate/2` rejeita termos não JSON antes do JSV, desabilita casts, reutiliza a root compilada e devolve o payload original ou um erro Leafcutter com paths e kinds ordenados, somente values JSON e sem messages dependentes do payload. PackageVersion publica uma source e uma ou mais destinations ordenadas; toda nova publicação exige `manifest_sha256` lowercase hex de 64 caracteres e globalmente único. O modelo físico mantém a coluna nullable para rows históricas, enquanto CHECK e trigger selam novos inserts e a mutation trigger impede troca do digest durante a publicação. Antes de inserir cada endpoint, a boundary confirma que sua ContractVersion possui schema persistido e faz rollback integral com erro em `contract_version_id` para versões legadas. PackageVersions históricas com ContractVersions legadas ou sem digest permanecem legíveis. Constraints e triggers continuam protegendo cardinalidade, compatibilidade de Operation role, referências, sealing e imutabilidade. Names, versions e refs rejeitam UTF-8 inválido antes da persistência.

A rejeição de ContractVersions legadas em novas PackageVersions, novos Deployments e novas Runs resolvidas está materializada. PackageVersions, Deployments, Runs e RunSnapshots históricos permanecem legíveis sem reescrita.

### Package Manifest e binding compilada

`LeafcutterConnectors.Package.Manifest` valida Manifest v1 com limites de bytes, profundidade e
nós, rejeita UTF-8/chaves duplicadas, aplica o schema JSV e as invariantes de whitespace/refs e
calcula SHA-256 sobre bytes exatos. `LeafcutterConnectors.Package` lê o manifest em compile
time, registra `@external_resource`, embute a projeção/digest e liga refs a módulos literais
Read/Write com cobertura, ordem, unicidade e behaviour conformance. Os callbacks são puros e
não leem filesystem; a fixture é somente de conformance.

`LeafcutterRuntime.ExecutablePackages.Inventory` embute a lista validada em compile time.
O build rejeita shape, duplicidade, path/realpath, project/manifest, dependency direction,
digest, ownership de app, external resource, topology e behaviour divergentes antes de
produzir o runtime. Cada entry vira dependency Mix `:path`; `mix quality` prova a application
closure da release e executa compile, format, tests e Dialyzer de cada package listado. A
fixture é dependency somente em test e não entra na release.

`LeafcutterRuntime.ExecutablePackages.resolve/1` busca a projeção imutável pela API pública do
Catalog, seleciona uma binding pelo digest exato, revalida name/version/topologia/módulos e
compõe refs e módulos literais com `operation_id` e `contract_version_id` autoritativos. A
binding resultante existe somente em memória. Deployment create/replace rejeita
PackageVersion histórica sem digest, e a criação de Run repete a resolução antes de persistir
Run/RunSnapshot.

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

`leafcutter_api` possui Phoenix Endpoint/Router/Telemetry básicos. `leafcutter_connectors`
materializa a boundary executável de Operation, o Transport HTTP 26C1 e o contract de Manifest
e binding compilada do passo 35. O passo 36 persiste o digest na PackageVersion, sob ownership
do Catalog. `LeafcutterConnectors.Application` supervisiona
exclusivamente a instância Finch HTTP/1; a application não depende de Core, Ecto, Repo ou
runtime.

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
Fluxo HTTP real
Integration Packages de produto
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
HTTP Transport contract and Slice 26C sequencing ratification
HTTP Transport boundary materialization
Package Manifest/build binding/module resolution ratification
Package Manifest v1 validation materialization
Compiled Package binding contract materialization
PackageVersion manifest digest persistence and legacy compatibility
Explicit package build inventory and release closure
Compiled runtime package resolution
EnvironmentDeployment executable package enforcement
Run executable package enforcement
Local derived knowledge base governance
Local knowledge schema and Claude adapters
Knowledge lint in mix quality
```

## Em andamento

Os Slices 26A, 26B, 26C1 e 26C2 estão integralmente materializados. O Transport HTTP pertence
a `leafcutter_connectors`; sua única árvore de processo nova supervisiona o pool Finch HTTP/1.
A facade valida os dois lados do adapter contract e faz exatamente uma tentativa bounded.

Manifest/build/module resolution possui contract fechado no ADR-0023 e os passos 35–38 estão
materializados em `leafcutter_connectors`, `leafcutter_core` e `leafcutter_runtime`. O Manifest
v1 não contém UUIDs nem modules; PackageVersion pinna seu digest, `packages/build.exs`
seleciona dependencies literais da release e o runtime combina somente módulos compilados com
a projeção pública do Catalog. Deployment e Run repetem a enforcement ratificada. O primeiro
fluxo de produto e suas matrizes vendor-specific por endpoint pertencem a 26C3.

## Próxima tarefa concreta

Ratificar o incremento 26C3 antes de materializar o primeiro fluxo completo de produto:

~~~text
select one complete external flow across one or more real systems
→ select exactly one Read source and one or more Write destinations
→ ratify authentication and vendor codec for every selected endpoint
→ ratify Read pagination and Write batch semantics
→ ratify status, rate-limit and vendor-error mapping per endpoint
→ define the product package and deterministic conformance matrix
~~~

26C3 precisa selecionar um fluxo executável completo, possivelmente entre mais de um sistema:
uma source Read real e uma ou mais destinations Write reais. Autenticação, codec, paginação
ou batch e o mapeamento de status/rate-limit/errors precisam ser fechados para cada endpoint
antes da implementação. Uma Operation isolada não satisfaz a topologia ratificada de Package.
Não criar package demonstrativo genérico, registry temporário ou execução parcial para
antecipar essa decisão.

A inventory de produção permanece vazia até 26C3. Fixture de conformance é test-only. Persisted
Attempt/Delivery errors, backoff, idempotency, durable fan-out e Broadway continuam fora.

## Principais decisões abertas

- fluxo externo completo, endpoints Read/Write e suas matrizes de status/rate-limit/vendor mapping (26C3);
- artifact signing/distribution, package retention e rolling upgrade;
- request payload/batch limits além do response body cap do Transport;
- data plane e durable fan-out;
- lifecycle completo de Run;
- autenticação e secrets;
- OpenAPI/error envelope;
- durable cross-context facts;
- infraestrutura/cluster de produção;
- retenção e storage tiers.

## Leitura relevante

- `docs/decisions/ADR-0023-package-manifest-build-binding-module-resolution.md`
- `docs/specifications/package-manifest-v1.md`
- `docs/decisions/ADR-0007-integration-packages.md`
- `docs/decisions/ADR-0022-transport-http-e-sequencia-26c.md`
- `docs/specifications/http-transport.md`
- `docs/decisions/ADR-0021-operation-executavel.md`
- `docs/specifications/operation-contract.md`
- `docs/decisions/ADR-0008-connector-operation-transport.md`
- `docs/architecture/connectors-operations-transports.md`
- `docs/specifications/error-retry-model.md`
- `docs/architecture/integration-packages.md`
- `docs/decisions/ADR-0009-at-least-once.md`
- `docs/decisions/ADR-0005-broadway-como-data-plane.md`
- `docs/decisions/ADR-0010-fanout-duravel-sem-fila-externa.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/transformations-enrichments-interceptors.md`
- `docs/architecture/estado-atual-e-visao-futura.md`
- `docs/architecture/decisoes-em-aberto.md`
- `docs/decisions/ADR-0019-contract-version-executavel-json-schema-jsv.md`
- `docs/specifications/contract-version-execution.md`
