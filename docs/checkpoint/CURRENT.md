# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Architecture consolidation - Context Map and umbrella application boundaries**

## Repository state

- Projeto criado como umbrella vazia com `mix new leafcutter --umbrella`.
- Base de documentação arquitetural preparada.
- Nenhuma application de domínio deve ser criada antes da ratificação do Context Map e do grafo de apps.
- `Organizations` ratificado.
- `Catalog` ratificado.

## Accepted architecture baseline

- Umbrella com poucas OTP applications.
- Toda OTP application deve possuir árvore de supervisão desde sua criação.
- Contexts só recebem supervisors próprios quando possuem processos com lifecycle que justifiquem uma subtree dedicada.
- Uma release inicial, preparada para separação futura.
- Phoenix Contexts maduros com facade raiz pequena, capability modules e implementação interna.
- Comunicação entre contexts ocorre somente por APIs públicas.
- PostgreSQL é a autoridade durável.
- OTP representa estado operacional reconstruível.
- PubSub é usado para propagação efêmera de fatos.
- Trabalho que não pode ser perdido deve possuir representação durável.
- Oban é usado quando adequado a jobs duráveis, scheduling, notificações, manutenção ou trabalho futuro.
- Broadway é o data plane para source, enrichments opcionais e destinations.
- JSON Schema Draft 2020-12 é o contrato canônico de payload, validado inicialmente com JSV.
- Integration Packages são versionados, declarados por `manifest.json` e inicialmente compilados com a mesma release.
- Connector -> Operation -> Transport.
- Transformation é pura.
- Enrichment representa side effects externos controlados.
- Interceptor atua na adaptação de transporte.
- Fan-out durável usa `Record + N Deliveries` persistidos em batch.
- Nenhuma fila externa é necessária inicialmente.
- Semântica base `at-least-once`.
- Ownership de Run por node utiliza heartbeat por node, `owner_node` e `generation` como fencing token.
- API-first com OpenAPI canônico e Postman derivado.
- Código e documentação in-code em inglês.
- Arquitetura externa em português brasileiro.
- O desenvolvedor é o autor principal; agentes atuam prioritariamente como guias, revisores e parceiros de implementação.

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

Owns conceitualmente:

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

API pública inicial:

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

Dependências:

```text
Organizations
→ nenhuma dependência de domínio
```

Decisões importantes:

- `Environment` pertence a `Organizations`.
- `User` e `ServiceAccount` são atores e sujeitos de autorização.
- mecanismos concretos de autenticação ficam fora do context.
- RBAC pertence a `Organizations`.
- não existe necessidade atual de processos OTP próprios do context.
- o app que hospedar o context será supervisionado desde sua criação.

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

dos building blocks reutilizáveis da plataforma.

Owns conceitualmente:

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

publication metadata
availability metadata
organization scope for private entries
```

API pública inicial:

```text
Catalog
├── Catalog.Packages
├── Catalog.Contracts
└── Catalog.Connectors
```

Escopos suportados:

```text
platform-wide
organization-scoped
```

A implementação executável de Connectors, Operations e Integration Packages não pertence ao Catalog.

Dependências:

```text
Catalog
   ↓
Organizations
```

`Catalog` depende apenas da API pública de `Organizations`.

Não depende de:

```text
Connections
Integrations
Executions
Notifications
Audit
```

Não existe necessidade atual de processos OTP próprios do context.

## Ratified dependency graph

Até o momento:

```text
Catalog
   ↓
Organizations
```

`Organizations` é a boundary de fundação.

O restante do grafo permanece em aberto.

## In progress

Ratificar os contexts restantes, um por vez:

1. `Connections`
2. `Integrations`
3. `Executions`
4. `Notifications`
5. `Audit`

Depois da ratificação dos contexts:

1. revisar ownership conjunto;
2. revisar APIs públicas e capability modules;
3. ratificar boundaries das OTP applications;
4. ratificar grafo de dependências entre apps;
5. criar as primeiras applications da umbrella.

## Next concrete task

Revisar o context proposto `Connections`.

Primeira decisão:

```text
Qual é exatamente a responsabilidade de domínio de Connections?
```

Nenhum app, schema, migration ou código de domínio deve ser criado durante essa decisão.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/connectors-operations-transports.md`
- `docs/architecture/ambientes-rbac-homologacao.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Open warnings

- `Connections`, `Integrations`, `Executions`, `Notifications` e `Audit` ainda são propostas.
- A divisão das OTP applications ainda não foi ratificada.
- Nenhuma application de domínio deve ser criada ainda.
- O mecanismo físico para compilar `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo do `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
