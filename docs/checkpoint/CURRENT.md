# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Architecture consolidation - Context Map and umbrella application boundaries**

## Repository state

- Projeto criado como umbrella vazia com `mix new leafcutter --umbrella`.
- Nenhuma application de domínio deve ser criada antes da ratificação do Context Map e do grafo de apps.
- `Organizations` ratificado.
- `Catalog` ratificado.
- `Connections` ratificado.
- `Integrations` ratificado.
- `Executions` ratificado.

## Accepted architecture baseline

- Umbrella com poucas OTP applications.
- Toda OTP application possui árvore de supervisão desde sua criação.
- Contexts recebem subtrees próprias quando processos reais justificarem isso.
- Phoenix Contexts maduros com facade raiz pequena, capability modules e implementação interna.
- Contexts se comunicam somente através de APIs públicas.
- PostgreSQL é a autoridade durável.
- OTP representa estado operacional reconstruível.
- PubSub propaga fatos efêmeros.
- Trabalho que não pode ser perdido possui representação durável.
- Oban é utilizado quando adequado a jobs duráveis, scheduling, notificações, manutenção ou trabalho futuro.
- Broadway é o data plane para source, enrichment e destinations.
- JSON Schema Draft 2020-12 é o contrato canônico de payload, inicialmente validado com JSV.
- Integration Packages são versionados e declarados por `manifest.json`.
- Connector -> Operation -> Transport.
- Transformation é pura.
- Enrichment representa side effects externos controlados.
- Interceptor atua na adaptação de transporte.
- Fan-out durável utiliza `Record + N Deliveries`.
- Sem fila externa inicialmente.
- Semântica base `at-least-once`.
- API-first com OpenAPI canônico.
- Código e documentação in-code em inglês.
- Arquitetura externa em português brasileiro.

## Ratified Contexts

### Organizations

Responsabilidade:

```text
tenancy
+
operational scope
+
authorization
```

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

API:

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

Dependências:

```text
nenhuma
```

---

### Catalog

Responsabilidade:

```text
registro
+
versionamento
+
publicação
+
disponibilidade
+
descoberta
```

Owns:

```text
Connector metadata
Operation metadata
Connector versions

Contract
ContractVersion

Package
PackageVersion
PackageDependency

CatalogCategory
publication / availability metadata
```

API:

```text
Catalog
├── Catalog.Packages
├── Catalog.Contracts
└── Catalog.Connectors
```

Dependências:

```text
Catalog
   ↓
Organizations
```

---

### Connections

Responsabilidade:

```text
representar
+
configurar
+
resolver
```

o acesso de `Organization + Environment` a sistemas externos.

Owns:

```text
Connection
Secret
SecretVersion

authentication configuration
OAuth token / refresh state
secret rotation metadata
```

API:

```text
Connections
└── Connections.Secrets
```

Dependências:

```text
Connections
   ├──→ Organizations
   └──→ Catalog
```

---

### Integrations

Responsabilidade:

```text
transformar um PackageVersion
em configuração executável
dentro de Organization + Environment
```

Distinção:

```text
PackageVersion
→ definição reutilizável

Integration
→ configuração concreta

Run
→ execução concreta
```

Owns:

```text
Integration
Destination configuration
Trigger
Schedule
configuration overrides
EnvironmentDeployment
HomologationRequest
Promotion
Rollback
IdentityMapping
Integration Labels
```

API:

```text
Integrations
├── Integrations.Destinations
├── Integrations.Triggers
├── Integrations.Deployments
├── Integrations.Homologations
└── Integrations.IdentityMappings
```

Dependências:

```text
Integrations
   ├──→ Organizations
   ├──→ Catalog
   └──→ Connections
```

---

### Executions

Responsabilidade:

```text
transformar uma Integration configurada
em uma execução concreta
+
durável
+
recuperável
```

Owns:

```text
Run
RunSnapshot

Record
Delivery
Attempt
Enrichment
Checkpoint

ExecutionEvent

owner_node
generation / fencing
recovery / claim state
node heartbeat relacionado ao ownership

RunCoordinator
Run supervision tree
Broadway pipelines
runtime Registry
Run DynamicSupervisor
```

Modelo principal:

```text
Run
└── Record
    └── Delivery
        └── Attempt
```

Estado adicional:

```text
Run
├── RunSnapshot
├── Checkpoint
├── ExecutionEvent
└── ownership / recovery state
```

API:

```text
Executions
├── Executions.Runs
├── Executions.Records
├── Executions.Deliveries
├── Executions.Attempts
└── Executions.Recovery
```

Dependências:

```text
Executions
├──→ Organizations
├──→ Catalog
├──→ Connections
└──→ Integrations
```

Decisões importantes:

- `RunSnapshot` é imutável.
- mudanças posteriores na Integration não alteram Runs já iniciados.
- `Record` representa um item extraído da origem.
- `Delivery` representa uma obrigação durável por destino.
- `Attempt` representa uma tentativa concreta de Delivery.
- `Enrichment` e `Checkpoint` fazem parte do estado durável da execução.
- `ExecutionEvent` registra fatos significativos do lifecycle.
- ownership de Run utiliza `owner_node + generation`.
- `generation` funciona como fencing token.
- heartbeat é por BEAM node, não por Run.
- PostgreSQL é a autoridade do ownership.
- semântica base é `at-least-once`.
- `Executions` é o primeiro Context ratificado com processos OTP próprios.
- cada Run possuirá subtree supervisionada.
- Broadway compõe o data plane.
- `RunCoordinator` compõe o control plane e não deve carregar Records.

## Ratified dependency graph

```text
Organizations
```

```text
Catalog
   ↓
Organizations
```

```text
Connections
   ├──→ Catalog
   └──→ Organizations
```

```text
Integrations
   ├──→ Connections
   ├──→ Catalog
   └──→ Organizations
```

```text
Executions
   ├──→ Integrations
   ├──→ Connections
   ├──→ Catalog
   └──→ Organizations
```

Nenhuma dependência circular foi introduzida.

## In progress

Ratificar os contexts restantes:

1. `Notifications`
2. `Audit`

Depois:

1. revisar o Context Map completo;
2. revisar ownership conjunto;
3. revisar APIs públicas;
4. revisar dependências entre contexts;
5. ratificar boundaries das OTP applications;
6. ratificar grafo de dependências entre apps;
7. criar as primeiras applications da umbrella.

## Next concrete task

Revisar o context proposto `Notifications`.

Primeira decisão:

```text
Qual é exatamente a responsabilidade de domínio de Notifications?
```

Nenhum app, schema ou migration deve ser criado durante essa decisão.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/observabilidade-e-auditoria.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Open warnings

- `Notifications` e `Audit` ainda são propostas.
- O Context Map completo ainda não passou pela revisão conjunta final.
- A divisão das OTP applications ainda não foi ratificada.
- Nenhuma application de domínio deve ser criada ainda.
- O mecanismo físico para compilar `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo do `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
