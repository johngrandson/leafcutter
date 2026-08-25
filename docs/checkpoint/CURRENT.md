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
- `Connections` ratificado.

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

Dependências:

```text
Catalog
   ↓
Organizations
```

### Connections

Responsabilidade:

```text
representar
+
configurar
+
resolver
```

o acesso de uma `Organization + Environment` a sistemas externos.

Owns conceitualmente:

```text
Connection
Secret
SecretVersion

authentication configuration
OAuth token / refresh state
secret rotation metadata
organization/environment scope
```

API pública inicial:

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

Decisões importantes:

- `Connection` contém configuração não sensível.
- `Secret` concentra credenciais sensíveis.
- `SecretVersion` suporta atualização e rotação.
- Connections são scoped por `Organization + Environment`.
- configuração e estado durável de OAuth pertencem a `Connections`.
- uma Connection referencia Connector conhecido pelo `Catalog`.
- `Connections` não conhece implementação concreta de Connector.
- `Connections` não depende de `Integrations`, `Executions`, `Notifications` ou `Audit`.
- não existe necessidade atual de processos OTP próprios do context.
- o app que hospedar `Connections` será supervisionado desde sua criação.

## Ratified dependency graph

Até o momento:

```text
Organizations
     ↑
     │
  Catalog
     ↑
     │
Connections
```

Com dependência direta adicional:

```text
Connections ─────→ Organizations
```

Em direção de dependência:

```text
Catalog
   ↓
Organizations

Connections
   ├──→ Catalog
   └──→ Organizations
```

## In progress

Ratificar os contexts restantes:

1. `Integrations`
2. `Executions`
3. `Notifications`
4. `Audit`

Depois:

1. revisar ownership conjunto;
2. revisar APIs públicas e capability modules;
3. ratificar boundaries das OTP applications;
4. ratificar grafo de dependências entre apps;
5. criar as primeiras applications da umbrella.

## Next concrete task

Revisar o context proposto `Integrations`.

Primeira decisão:

```text
Qual é exatamente a responsabilidade de domínio de Integrations?
```

Nenhum app, schema, migration ou código de domínio deve ser criado durante essa decisão.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/integration-packages.md`
- `docs/architecture/ambientes-rbac-homologacao.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Open warnings

- `Integrations`, `Executions`, `Notifications` e `Audit` ainda são propostas.
- A divisão das OTP applications ainda não foi ratificada.
- Nenhuma application de domínio deve ser criada ainda.
- O mecanismo físico para compilar `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo do `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
