# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Architecture consolidation - Context Map and umbrella application boundaries**

## Repository state

- Projeto criado como umbrella vazia com `mix new leafcutter --umbrella`.
- Base de documentação arquitetural preparada.
- Nenhuma application de domínio deve ser criada antes da ratificação do Context Map e do grafo de apps.
- `Organizations` foi ratificado como primeiro Phoenix Context.

## Accepted architecture baseline

- Umbrella com poucas OTP applications.
- Toda OTP application deve possuir árvore de supervisão desde sua criação.
- Contexts só recebem supervisors próprios quando possuem processos com lifecycle que justifiquem uma subtree dedicada.
- Uma release inicial, preparada para separação futura.
- Phoenix Contexts maduros com facade raiz pequena, capability modules e implementação interna.
- Comunicação entre contexts: API pública síncrona, PubSub efêmero e representação durável para trabalho que não pode ser perdido.
- Oban é usado quando adequado a jobs duráveis, scheduling, notificações, manutenção ou trabalho futuro.
- PostgreSQL como estado durável; OTP como estado operacional reconstruível.
- Um supervision subtree por Run.
- Broadway como data plane para source, enrichments opcionais e destinations.
- JSON Schema Draft 2020-12 como contrato canônico, validado inicialmente com JSV.
- Integration Packages versionados, declarados por `manifest.json` e inicialmente compilados com a mesma release.
- Connector -> Operation -> Transport.
- Transformation pura; Enrichment para side effects externos; Interceptor para transporte.
- Fan-out durável com `Record + N Deliveries` persistidos em batch e sem fila externa inicial.
- Semântica `at-least-once`.
- Ownership de Run por node com heartbeat por node, `owner_node` e `generation` como fencing token.
- API-first com OpenAPI canônico e Postman derivado.
- Código e docs in-code em inglês; arquitetura externa em pt-BR.
- Desenvolvedor como autor principal; agentes prioritariamente como guia, revisor e parceiro de implementação.

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

Decisões ratificadas:

- `Environment` pertence a `Organizations`.
- `User` e `ServiceAccount` pertencem ao context como atores e sujeitos de autorização.
- mecanismos concretos de autenticação ficam fora dessa boundary.
- RBAC pertence a `Organizations`.
- `Organizations` não depende de outros contexts de domínio.
- API pública inicial:

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

- não existe necessidade atual de um `Organizations.Supervisor` próprio.
- o app que hospedar o context será supervisionado desde sua criação.

## In progress

Ratificar os contexts restantes, um por vez:

1. `Catalog`
2. `Connections`
3. `Integrations`
4. `Executions`
5. `Notifications`
6. `Audit`

Depois:

1. revisar ownership conjunto dos conceitos;
2. revisar APIs públicas e capability modules;
3. ratificar apps da umbrella;
4. ratificar o grafo de dependências;
5. criar as primeiras OTP applications.

## Next concrete task

Revisar `Catalog` em `docs/architecture/contextos-e-ownership.md` e decidir primeiro sua responsabilidade de domínio.

Nenhum código ou application deve ser criado durante essa decisão.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/contracts-json-schema.md`
- `docs/architecture/integration-packages.md`
- `docs/architecture/connectors-operations-transports.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Open warnings

- `Catalog`, `Connections`, `Integrations`, `Executions`, `Notifications` e `Audit` ainda são propostas.
- A divisão das OTP applications ainda não foi ratificada.
- Nenhuma application de domínio deve ser criada ainda.
- O mecanismo físico para compilar conteúdo de `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo de `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
