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

### Catalog parcial

O Catalog mínimo ratificado está materializado:

```text
Connector
└── ConnectorVersion
    └── Operation

Contract
└── ContractVersion

Package
└── PackageVersion
    └── PackageVersionEndpoint
```

`Catalog.Connectors` expõe criação e leitura de Connector e publicação atômica de ConnectorVersion com suas Operations. A versão permanece não publicada somente dentro da transação de publicação; constraints e triggers impedem commit sem sealing, inclusão posterior de Operations, update e delete do conteúdo publicado. `Catalog.Contracts` expõe criação e leitura de Contract e publicação de ContractVersion identity-only, já selada no insert e imutável no PostgreSQL. `Catalog.Packages` cria e lê Package, publica PackageVersion com uma source e destinations ordenadas e lê a projeção completa por versão. PostgreSQL protege cardinalidade, compatibilidade de role, referências, sealing e imutabilidade. Os identificadores textuais desses agregados rejeitam UTF-8 inválido antes da persistência.

### Connections mínimo

```text
Environment
├── Connection
│   └── optional SecretVersion binding
└── Secret
    └── immutable SecretVersion
```

`Leafcutter.Connections` cria, lê, atualiza config/binding e desabilita Connections. `Leafcutter.Connections.Secrets` cria Secret e SecretVersion identities sem armazenar material secreto. Connection referencia Connector estável; config é um JSON object não sensível; o binding é opcional, exato e precisa pertencer ao mesmo Organization/Environment.

Writes validam Organization e Environment ativos por uma API pública do owner que segura locks compartilhados na ordem Organization → Environment. FKs compostas impedem scope incompatível, um trigger protege o binding de SecretVersion cross-scope e PostgreSQL rejeita update/delete de SecretVersion. Raw secret, ciphertext, provider locator, credential, OAuth e rotation permanecem fora do slice.

### Integrations parcial

`Leafcutter.Integrations` cria, lê e desabilita identidades Integration organization-scoped ligadas a uma Package estável. Organization, Package e name são imutáveis depois da criação. Writes validam a Organization ativa sob lock compartilhado, e disable preserva um único timestamp sob locks na ordem Organization → Integration.

### Runtime e Executions foundation

Persistência atual:

```text
RuntimeNode
Run
RunSnapshot
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

`RunSnapshot` usa o id de `Run` como primary key, congela a definition v1 estruturalmente validada e rejeita updates no PostgreSQL. `Runs.create/1` persiste Run `pending` e snapshot atomicamente. `Runs.fetch_snapshot/1` fornece leitura explícita.

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
→ starts pending Runs with a snapshot in a supported format
→ FOR UPDATE SKIP LOCKED
→ starts local trees after commit
```

Runs `pending` sem snapshot ou com formato desconhecido permanecem inelegíveis. Runs legadas `running` preservam recovery independentemente do snapshot.

Falhas operacionais retornadas pelo contrato de recovery e exceções esperadas de banco entram no backoff global. Erros de programação encerram o processo e são tratados pela supervisão, sem serem mascarados como falhas retryable.

### API atual

`leafcutter_api` é uma application Phoenix API-only com Endpoint, Router, Telemetry e error JSON básicos. Autenticação concreta, OpenAPI completo e endpoints de produto ainda não foram materializados.

### Connectors atuais

`leafcutter_connectors` existe como OTP application e boundary, mas ainda não possui behaviours, transports ou implementações executáveis de connector.

## Arquitetura ratificada ainda não materializada

### Catalog futuro

O modelo mínimo ratificado no ADR-0018 está materializado. Permanecem posteriores:

```text
availability/deprecation metadata
Package Manifest e build
ContractVersion JSON Schema/JSV
```

O slice materializado usa identidades globais estáveis, versões nascidas publicadas e uma projeção relacional de endpoints de PackageVersion. Todo o conteúdo versionado do Catalog mínimo é imutável. Package Manifest, JSON Schema/JSV e availability lifecycle permanecem posteriores.

### Connections futuro

O modelo mínimo de Connection, Secret e SecretVersion está materializado. Permanecem ratificados ou abertos para slices posteriores:

```text
OAuth durable state
secret provider/encryption
rotation and revocation metadata
retention lifecycle
```

Raw secrets continuam fora de PackageVersion, RunSnapshot, logs, AuditEvent e respostas de API. Provider, encryption, OAuth, rotation, revocation e retention exigem decisões próprias antes de implementação.

### Integrations futuro

O restante do modelo mínimo foi ratificado no ADR-0018 e ainda não está materializado:

```text
EnvironmentDeployment
Triggers
HomologationRequest
Promotion history
IdentityMapping
```

EnvironmentDeployment persistirá PackageVersion, promotable/local config e bindings por endpoint. Promotion continua futura e copiará somente estado promovível; não copiará secrets, Connections, Triggers ou config local do target.

### Executions completo

RunSnapshot v1 já está materializado conforme `docs/decisions/ADR-0017-run-snapshot-v1.md` e `docs/specifications/run-snapshot-v1.md`.

Continuam planejados:

```text
Record
Delivery
Attempt
Checkpoint
ExecutionEvent
Enrichment execution state
```

A criação a partir de EnvironmentDeployment foi ratificada no ADR-0018 e em sua specification, mas ainda não foi materializada. O workflow pertence à orchestration em leafcutter_runtime, resolve as authorities upstream em uma transação e entrega a definition pronta a Executions.

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

- lifecycle de availability/deprecation das versões do Catalog;
- metadata ampliada das authorities upstream;
- política de rolling upgrade e formatos de RunSnapshot suportados;
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

Catalog, Connections e a identidade de Integration estão materializados. A próxima fronteira segue a ordem ratificada:

```text
Catalog mínimo (materializado)
↓
Connections + SecretVersion bindings (materializado)
↓
Integration identity (materialized)
↓
EnvironmentDeployment + bindings
↓
resolver em leafcutter_runtime
↓
Executions.Runs.create/1
```

O ADR-0018 e a specification correspondente controlam esses sub-slices. RunSnapshot continua provando somente presença e versão suportada no control plane. O carregamento no coordinator e a execução Broadway permanecem posteriores.
