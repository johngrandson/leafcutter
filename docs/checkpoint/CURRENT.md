# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Architecture consolidation - full Context Map review**

## Repository state

- Projeto criado como umbrella vazia com `mix new leafcutter --umbrella`.
- Nenhuma application de domínio foi criada.
- `Organizations` ratificado.
- `Catalog` ratificado.
- `Connections` ratificado.
- `Integrations` ratificado.
- `Executions` ratificado.
- `Notifications` ratificado.
- `Audit` ratificado.
- Primeira rodada individual do Context Map concluída.

## Accepted architecture baseline

- Umbrella com poucas OTP applications.
- Toda OTP application possui árvore de supervisão desde sua criação.
- Contexts recebem subtrees próprias somente quando processos reais justificarem isso.
- Phoenix Contexts maduros com facade raiz pequena, capability modules e implementação interna.
- Contexts não acessam schemas ou queries internos de outros contexts.
- Comunicação entre contexts utiliza APIs públicas ou mecanismos explicitamente ratificados.
- PostgreSQL é a autoridade durável.
- OTP representa estado operacional reconstruível.
- PubSub propaga fatos efêmeros.
- Trabalho que não pode ser perdido possui representação durável.
- Oban é usado quando adequado a jobs duráveis, scheduling, notificações, manutenção ou trabalho futuro.
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

Dependências:

```text
nenhuma
```

OTP próprio:

```text
não inicialmente
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

Dependências:

```text
Catalog
   ↓
Organizations
```

OTP próprio:

```text
não inicialmente
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

Dependências:

```text
Connections
   ├──→ Organizations
   └──→ Catalog
```

OTP próprio:

```text
não inicialmente
```

---

### Integrations

Responsabilidade:

```text
transformar um PackageVersion
em configuração executável
dentro de Organization + Environment
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

Dependências:

```text
Integrations
   ├──→ Organizations
   ├──→ Catalog
   └──→ Connections
```

OTP próprio:

```text
não inicialmente
```

---

### Executions

Responsabilidade:

```text
transformar uma Integration configurada
em execução concreta
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

ownership / fencing / recovery state
node heartbeat relacionado a Run ownership

RunCoordinator
Run supervision tree
Broadway pipelines
runtime Registry
Run DynamicSupervisor
```

Dependências:

```text
Executions
├──→ Organizations
├──→ Catalog
├──→ Connections
└──→ Integrations
```

OTP próprio:

```text
sim
```

`Executions` é o primeiro context ratificado com processos OTP próprios desde o início.

---

### Notifications

Responsabilidade:

```text
transformar eventos relevantes
em notificações duráveis
para recipients configurados
```

Owns:

```text
NotificationRule
NotificationChannel
Recipient
NotificationDelivery
```

`Recipient` é independente de `User`.

Dependências:

```text
Notifications
├──→ Organizations
├──→ Integrations
└──→ Executions
```

Durabilidade inicial:

```text
NotificationDelivery
+
PostgreSQL
+
Oban
```

OTP próprio:

```text
não inicialmente
```

---

### Audit

Responsabilidade:

```text
registrar ações humanas
e administrativas relevantes
de forma durável e consultável
```

Owns:

```text
AuditEvent
actor metadata
action
target reference
Organization / Environment scope
redacted change metadata
```

Dependências:

```text
Audit
   ↓
Organizations
```

Audit é um sink.

Outros contexts não utilizam Audit para decidir regras de negócio.

OTP próprio:

```text
não inicialmente
```

## Ratified dependency graph

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

```text
Notifications
   ├──→ Executions
   ├──→ Integrations
   └──→ Organizations
```

```text
Audit
   └──→ Organizations
```

Nenhuma dependência circular conhecida foi introduzida na primeira rodada.

## Completed milestone

```text
Individual Context Ratification
```

Concluído para:

```text
Organizations
Catalog
Connections
Integrations
Executions
Notifications
Audit
```

## In progress

Revisar o Context Map como sistema completo.

A revisão deve procurar:

1. responsabilidades duplicadas;
2. boundaries excessivamente grandes;
3. contexts desnecessariamente pequenos;
4. dependências redundantes;
5. dependências circulares indiretas;
6. APIs públicas excessivas;
7. concepts posicionados no context errado;
8. responsabilidades de infraestrutura misturadas com domínio.

## Next concrete task

Executar uma revisão conjunta de:

```text
Organizations
Catalog
Connections
Integrations
Executions
Notifications
Audit
```

Nenhuma OTP application deve ser criada durante essa revisão.

Depois da aprovação do mapa completo:

```text
Context Map
        ↓
OTP application boundaries
        ↓
dependency graph between apps
        ↓
create apps/
```

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/modelo-conceitual.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/ambientes-rbac-homologacao.md`
- `docs/architecture/observabilidade-e-auditoria.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Open warnings

- O Context Map foi ratificado individualmente, mas ainda precisa passar pela revisão conjunta.
- A divisão das OTP applications ainda não foi ratificada.
- Nenhuma application de domínio deve ser criada ainda.
- O grafo de dependências entre OTP applications ainda não foi congelado.
- O mecanismo físico para compilar `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo do `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
