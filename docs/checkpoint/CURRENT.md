# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Run definition and snapshot foundation**

A primeira foundation funcional de RBAC de `Organizations` está concluída para
`User` e `ServiceAccount`.

A infraestrutura OTP mínima de `leafcutter_runtime`, liveness por incarnação,
Run ownership/fencing, a primeira árvore local por Run e recovery automático de Runs
`running` estão materializados.

## Repository state

A umbrella contém quatro OTP applications:

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
  `LeafcutterRuntime.RunDynamicSupervisor`, `LeafcutterRuntime.NodeHeartbeat` e
  `LeafcutterRuntime.RunRecovery`;
- `leafcutter_api` é Phoenix API-only com Endpoint e Telemetry;
- `Organizations` possui Organization, Environment, User, ServiceAccount,
  Membership, Role, Permission e assignments organization/environment-scoped;
- `Organizations.Access.authorize/3` resolve User ou ServiceAccount sem
  `Principal` persistido;
- assignments organization-wide satisfazem checks em Environment;
- assignments environment-scoped não satisfazem Organization nem outro Environment;
- `Executions` possui `RuntimeNode`, `Run`, `Nodes.heartbeat/2`, `Runs.claim/2`,
  `Runs.release/1`, `Runs.list_owned_tokens/1` e `Runs.claim_recoverable/3`;
- `RuntimeNode.id` identifica uma incarnação específica da application runtime;
- `node_name` é metadata reutilizável e deliberadamente não possui unicidade;
- heartbeat, expiração e ownership usam o relógio do PostgreSQL;
- reiniciar apenas `NodeHeartbeat` preserva o `runtime_node_id`;
- reiniciar a application/BEAM gera outro `runtime_node_id`;
- Runs começam em `pending`, mudam para `running` no primeiro claim explícito e
  possuem estados terminais `completed`, `failed` e `cancelled`;
- `owner_node_id` referencia uma incarnação e `generation` é o fencing token
  monotônico;
- runtime nodes expiram após 45 segundos sem heartbeat;
- claim/reclaim explícito é serializado por row lock na Run;
- release aplica `run_id + owner_node_id + generation` no mesmo UPDATE;
- `LeafcutterRuntime.Runs.start/1` faz claim antes do startup local;
- `LeafcutterRuntime.Runs.start_claimed/1` inicia a árvore usando token já committed;
- `LeafcutterRuntime.Runs.list_local/0` expõe somente árvores locais vivas;
- `LeafcutterRuntime.Runs.stop/1` tenta release e encerra a árvore local;
- `LeafcutterRuntime.Runs.stale_ownership/1` encerra somente a generation local
  correspondente ao token rejeitado;
- `RunSupervisor` e `RunCoordinator` estão materializados sem Broadway;
- `RunRecovery` usa polling autoritativo a cada 5 segundos;
- recovery reconstrói árvores já owned pela incarnação local sem incrementar generation;
- recovery reivindica somente Runs `running` sem owner ou com owner expirado;
- recovery usa lotes de 25 ordenados por `updated_at + id` e
  `FOR UPDATE SKIP LOCKED` para distribuir concorrência entre nodes;
- Runs `pending` continuam exigindo start explícito até existir RunSnapshot;
- falhas globais de scan e falhas locais de startup possuem backoff em memória;
- shutdown normal tenta release best effort antes de encerrar árvores locais;
- crash isolado de `RunRecovery` não libera ownership nem remove árvores locais;
- testes cobrem constraints, lifecycle, concorrência, RBAC, heartbeat,
  ownership/fencing, supervisão local e recovery automático;
- RunSnapshot, criação pública de Run e data plane ainda não foram criados.

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

Todos possuem zero dependências diretas de domínio entre si:

```text
Organizations   → none
Catalog         → none
Connections     → none
Integrations    → none
Executions      → none
Notifications   → none
Audit           → none
```

Cross-context use cases são compostos por application workflow modules na OTP
application que possui o use case.

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

Ratificações:

- `Operation` pertence a `ConnectorVersion`;
- não existe `OperationVersion` inicialmente;
- versões publicadas de Package, Connector e Contract são imutáveis;
- `PackageDependency` foi removido do V1;
- categorias são metadata;
- PackageVersion inicial possui exatamente 1 Source e 1..N Destinations.

### Connections

Owns:

```text
Connection
Secret
SecretVersion
auth configuration
OAuth durable state
rotation metadata
```

`Connection` referencia Connector identity, não ConnectorVersion.

### Integrations

Owns Integration e sua configuração executável por Environment.

```text
Integration
└── EnvironmentDeployment
```

Ratificações:

- EnvironmentDeployment seleciona PackageVersion;
- Connection bindings e Triggers são environment-local;
- promotable config é separado de environment-local config;
- HomologationRequest aprova um state fingerprint específico;
- Promotion não copia secrets, connections ou triggers;
- Rollback é operação, não entidade inicial;
- IdentityMapping pertence a Integrations e é scoped por deployment/destination.

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

Owns `AuditEvent`, append-only e imutável.

Audit é sink e não participa de decisões de negócio de outros contexts.

## Cross-context durable facts

Notifications e Audit consomem fatos duráveis self-contained.

Quando a emissão do fato é obrigação do sistema, ele deve ser persistido
atomicamente com a mudança de domínio que o originou.

Não criar um Context `Events` ou `Outbox`.

`ExecutionEvent` permanece restrito ao lifecycle de execução.

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
shared transport infrastructure
```

### `leafcutter_runtime`

Hosts:

```text
Executions
runtime application workflows
RunRegistry
RunDynamicSupervisor
NodeHeartbeat
RunRecovery
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

## Shared infrastructure decisions

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

Isso inclui tabelas owned por `Executions`, como `runtime_nodes` e `runs`.

## Runtime baseline

Supervision tree da application:

```text
LeafcutterRuntime.Application
├── LeafcutterRuntime.RunRegistry
├── LeafcutterRuntime.RunDynamicSupervisor
├── LeafcutterRuntime.NodeHeartbeat
└── LeafcutterRuntime.RunRecovery
```

`RunRegistry` é local e possui keys `:unique`.

Authority durável:

```text
RuntimeNode
└── last_heartbeat_at

Run
├── status
├── owner_node_id
├── generation
└── ownership_acquired_at
```

Semântica de claim explícito:

```text
sem owner
→ claim + generation incrementada

owner expirado
→ reclaim + generation incrementada

mesmo owner ativo
→ token atual sem incremento

outro owner ativo
→ claim rejeitado
```

Toda escrita crítica futura deve aplicar:

```text
run_id + runtime_node_id + generation
```

no mesmo comando SQL que altera o estado.

## Per-Run supervision baseline

Workflow explícito de startup:

```text
LeafcutterRuntime.Runs.start(run_id)
↓
Executions.Runs.claim(run_id, runtime_node_id)
↓
RunDynamicSupervisor
└── RunSupervisor <run_id>
    └── RunCoordinator
```

Workflow depois de claim já committed:

```text
LeafcutterRuntime.Runs.start_claimed(ownership_token)
↓
RunDynamicSupervisor
└── RunSupervisor <run_id>
    └── RunCoordinator
```

Registry local:

```text
run_id
→ RunSupervisor PID + ownership_token

{:coordinator, run_id}
→ RunCoordinator PID + ownership_token
```

Semântica:

```text
mesma generation já local
→ retorna o mesmo supervisor

generation local antiga
→ encerra árvore antiga
→ inicia árvore com token atual

RunCoordinator crash anormal
→ coordinator reiniciado

RunCoordinator recebe stale token correspondente
→ exit normal
→ RunSupervisor auto-shutdown
→ generation stale não reiniciada
```

`RunSupervisor` é transient sob o DynamicSupervisor. `RunCoordinator` é transient e
significant, permitindo restart em crash e shutdown completo em stale ownership.

Start explícito, start por token e stop local são serializados por Run no Registry.

Stop explícito tenta release durável antes de remover a árvore. Um release stale não
mantém processos locais vivos.

## Automatic recovery baseline

```text
RunRecovery
↓ polling
list durable tokens owned by this runtime node
↓
reconcile local Registry
↓
claim running recoverable Runs
FOR UPDATE SKIP LOCKED
↓
start_claimed(token)
```

Reconciliação de Runs já owned:

```text
token durável + árvore ausente
→ reconstruir sem incrementar generation

token durável == token local
→ no-op

token local diferente ou sem ownership durável correspondente
→ encerrar generation local como stale
```

Claim automático:

```text
status == running
AND owner is nil or expired
→ bounded claim batch
→ generation + 1
→ commit
→ local startup
```

Configuração inicial:

```text
scan interval     5 segundos
batch size        25
drain delay       100 ms
global backoff    1s até 30s
per-Run backoff   em memória
```

`FOR UPDATE SKIP LOCKED` evita que nodes concorrentes aguardem o mesmo lote. O
PostgreSQL continua sendo authority; não existe leader election para recovery.

Runs `pending` permanecem fora do scanner até existir uma definição executável
imutável.

Durante shutdown normal, recovery para scans e tenta release best effort das árvores
locais. Em indisponibilidade do banco, a expiração do heartbeat continua garantindo
reclaim posterior com nova generation.

Uma Run tree permanece em um único node inicialmente.

PostgreSQL é autoridade para liveness, ownership e fencing.

Sem `:global`, `:pg`, Horde ou lock distribuído customizado.

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

Todos os nodes executam inicialmente:

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

Durable Run Ownership + Fencing Foundation
→ completed

Per-Run Supervisor + Coordinator Foundation
→ completed

Automatic Run Recovery Bootstrap Foundation
→ completed
```

## In progress

Definir a representação executável e imutável que torna uma Run `pending` segura para
startup e recovery automáticos.

## Next concrete task

Ratificar o primeiro `RunSnapshot` e o workflow público de criação de Run:

```text
validated executable definition
↓ transaction
Run + immutable RunSnapshot
↓
pending Run becomes eligible for explicit or automatic startup
```

A decisão deve fechar:

- quais identidades estáveis de Integration, EnvironmentDeployment, PackageVersion e
  Connections são copiadas ou referenciadas;
- quais configurações precisam ser congeladas no snapshot;
- como secrets permanecem fora do payload imutável;
- relação 1:1 entre Run e RunSnapshot;
- atomicidade de criação;
- quando uma Run `pending` passa a ser elegível para o scanner;
- contrato de criação e erros públicos;
- quais mudanças futuras exigem nova Run em vez de mutação do snapshot.

Ainda não adicionar Broadway, Record/Delivery processing ou transitions completas de
pause/resume antes dessa definição executável estar fechada.

## Open warnings

- criação pública de Run, definição executável e RunSnapshot ainda não foram fechadas;
- transitions completas de lifecycle, pause/resume e terminalização ainda não foram fechadas;
- política de retenção/cleanup de runtime node incarnations ainda não foi fechada;
- autenticação concreta de ServiceAccount ainda não foi modelada;
- AuditEvent para histórico de RBAC ainda não foi materializado;
- mecanismo físico de inclusão de `packages/` no build ainda não foi ratificado;
- JSON Schema definitivo de `manifest.json` ainda não foi fechado;
- mecanismo físico de durable cross-context facts/outbox ainda não foi fechado;
- mecanismo concreto de historical deployment state ainda não foi fechado;
- cliente HTTP e pool strategy ainda não foram escolhidos;
- configuração concreta de Oban queues/plugins ainda não foi escolhida;
- endpoints e schemas dos demais contexts ainda não estão congelados.

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
