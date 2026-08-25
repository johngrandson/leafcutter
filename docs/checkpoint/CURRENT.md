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

## Accepted architecture baseline

- Umbrella com poucas OTP applications.
- Toda OTP application possui árvore de supervisão desde sua criação.
- Contexts só recebem supervisors próprios quando processos reais justificarem uma subtree.
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

API pública:

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
registrar
+
versionar
+
publicar
+
disponibilizar
+
permitir descoberta
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

API pública:

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

API pública:

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
em uma configuração executável
dentro de Organization + Environment
```

Distinção fundamental:

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

Uma `Integration`:

```text
belongs to
→ Organization + Environment

references
→ explicit PackageVersion
```

Upgrade de `PackageVersion` é explícito.

API pública:

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

`Integrations` não executa Runs.

Não possui necessidade atual de processos OTP próprios.

## Ratified dependency graph

```text
Organizations
     ↑
     │
  Catalog
     ↑
     │
Connections
     ↑
     │
Integrations
```

Com dependências diretas:

```text
Catalog
→ Organizations

Connections
→ Catalog
→ Organizations

Integrations
→ Connections
→ Catalog
→ Organizations
```

Nenhuma dependência circular foi introduzida.

## In progress

Ratificar os contexts restantes:

1. `Executions`
2. `Notifications`
3. `Audit`

Depois:

1. revisar o Context Map completo;
2. revisar ownership conjunto;
3. revisar APIs públicas;
4. ratificar boundaries das OTP applications;
5. ratificar o grafo de dependências entre apps;
6. criar as primeiras applications da umbrella.

## Next concrete task

Revisar o context proposto `Executions`.

Primeira decisão:

```text
Qual é exatamente a responsabilidade de domínio de Executions?
```

Nenhum app, schema ou migration deve ser criado durante essa decisão.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/durabilidade-e-recovery.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/modelo-conceitual.md`
- `docs/decisions/ADR-0005-broadway-como-data-plane.md`
- `docs/decisions/ADR-0009-at-least-once.md`
- `docs/decisions/ADR-0010-fanout-duravel-sem-fila-externa.md`
- `docs/decisions/ADR-0011-run-ownership-fencing.md`

## Open warnings

- `Executions`, `Notifications` e `Audit` ainda são propostas.
- A divisão das OTP applications ainda não foi ratificada.
- Nenhuma application de domínio deve ser criada ainda.
- O mecanismo físico para compilar `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo do `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
