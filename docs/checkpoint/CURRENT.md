# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Organizations RBAC foundation**

A infraestrutura compartilhada mínima de `leafcutter_core` está materializada e o
trabalho atual está concentrado no primeiro modelo de autorização do context
`Organizations`.

## Repository state

A umbrella contém quatro OTP applications materializadas:

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
- `leafcutter_runtime` possui supervision tree vazia;
- `leafcutter_api` é Phoenix API-only com Endpoint e Telemetry;
- migrations permanecem centralizadas em `apps/leafcutter_core/priv/repo/migrations/`;
- nenhum Run process, Broadway pipeline ou runtime Registry foi criado.

## Organizations implementation state

Schemas persistidos/representados:

```text
Organization
Environment
User
Membership
Role
RolePermission
RoleAssignment
```

`Permission` é uma primitive conhecida em código e não possui tabela própria.

Public surface implementada:

```text
Leafcutter.Organizations
├── create/1
├── get/1
└── disable/1

Leafcutter.Organizations.Environments
├── create/1
├── get/1
└── disable/1

Leafcutter.Organizations.Users
├── create/1
├── get/1
└── disable/1

Leafcutter.Organizations.Roles
├── create/1
├── get/1
├── disable/1
├── grant_permission/2
└── revoke_permission/2

Leafcutter.Organizations.Access
├── add_member/1
├── remove_member/2
├── assign_role/1
└── revoke_role/1
```

### Lifecycle baseline

`Organization`, `Environment`, `User`, `Membership` e `Role` usam `disabled_at`.

Operações de disable/remove são idempotentes e preservam o primeiro timestamp.

Locks `FOR UPDATE` são usados quando uma decisão de lifecycle precisa permanecer
válida até o commit.

### Membership

```text
User
  ↓
Membership
  ↓
Organization
```

Um `User` possui identidade global da plataforma e participa de Organizations por
`Membership`.

Existe no máximo um Membership durável por `organization_id + user_id`.

Membership desabilitado não é reativado implicitamente por `add_member/1`.

### Permission e Role

Permissions são atoms tipados no domínio e strings canônicas em persistence/external
boundaries.

Exemplo:

```text
:environment_read
↔
"environment.read"
```

`RolePermission` representa estado atual de permissions do Role:

```text
grant_permission
→ INSERT

revoke_permission
→ DELETE
```

Histórico de mudanças de permission pertence futuramente a `AuditEvent`.

### RoleAssignment

Role é atribuído inicialmente a um `Membership`:

```text
Membership
└── RoleAssignment
    ├── role_id
    └── environment_id | nil
```

Semântica:

```text
environment_id == nil
→ assignment organization-wide

environment_id != nil
→ assignment restrito ao Environment
```

`RoleAssignment` não possui ID próprio nem lifecycle separado. Representa estado
corrente de autorização:

```text
assign_role
→ INSERT

revoke_role
→ DELETE
```

Invariantes de `assign_role/1`:

- Organization do Membership deve existir e estar ativa;
- Membership deve existir e estar ativo;
- Role deve existir, estar ativo e pertencer à mesma Organization;
- Environment opcional deve existir, estar ativo e pertencer à mesma Organization;
- organization-wide e environment-scoped assignments podem coexistir;
- o mesmo Role não pode ser duplicado no mesmo scope para o mesmo Membership.

Revogação é idempotente e pode reduzir acesso mesmo quando os recursos relacionados
já estão desabilitados.

## Tests

A suíte de `leafcutter_core` usa SQL Sandbox.

A cobertura atual inclui, entre outros:

- validação e constraints dos schemas de Organizations;
- lifecycle idempotente;
- criação de Environment apenas sob Organization ativa;
- criação/remoção de Membership;
- concorrência envolvendo lifecycle e membership creation/removal;
- Role lifecycle;
- grant/revoke de Permission;
- RoleAssignment organization-wide e environment-scoped;
- mismatch de Organization para Role/Environment;
- duplicate assignment por scope;
- revogação idempotente e scope-specific de RoleAssignment.

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

## Ratified OTP application boundaries

```text
leafcutter_core
→ Organizations + Catalog + Connections + Integrations + Notifications + Audit
→ Leafcutter.Repo + Leafcutter.PubSub + Oban

leafcutter_connectors
→ Connector / Operation / Transport runtime code

leafcutter_runtime
→ Executions + runtime workflows + OTP runtime infrastructure

leafcutter_api
→ Phoenix HTTP boundary + authentication/authorization boundary + OpenAPI
```

## Ratified app dependency graph

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → leafcutter_core + leafcutter_connectors
leafcutter_api        → leafcutter_core + leafcutter_runtime
```

## Shared infrastructure decisions

Ratificado:

```text
one Leafcutter.Repo
→ leafcutter_core

one Leafcutter.PubSub
→ leafcutter_core

one Oban infrastructure
→ leafcutter_core
```

PostgreSQL continua sendo a autoridade durável.

## Runtime baseline

Runtime supervision conceitual permanece ratificada, mas ainda não materializada:

```text
LeafcutterRuntime.Application
├── Registry
├── Run DynamicSupervisor
└── NodeHeartbeat
```

Cada Run futuramente possui subtree própria com `RunCoordinator` e Broadways.

Sem `:global`, Horde ou fila externa inicialmente.

## Integration Packages

Ratificado:

```text
packages/<package>/
├── mix.exs
├── manifest.json
├── lib/
└── test/
```

Cada Package é um Mix project independente fora de `apps/` e será compilado na
mesma release inicial.

O mecanismo físico para incluí-los no build ainda está aberto.

## Release

Uma única release inicial:

```text
:leafcutter
```

Todos os nodes executam a mesma release completa inicialmente.

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
```

## In progress

Completar a primeira foundation de RBAC de `Organizations`.

O modelo de `RoleAssignment` organization-wide/environment-scoped está sendo
materializado e testado.

## Next concrete task

Depois da ratificação/merge de `RoleAssignment`, definir a semântica de avaliação de
autorização antes de implementar:

```text
Organizations.Access.authorize(...)
```

A próxima decisão deve esclarecer como organization-wide e environment-scoped
assignments participam da resolução de Permission e como lifecycle de `User`,
`Membership`, `Role` e `Environment` afeta a decisão.

`ServiceAccount` continua owned por Organizations, mas ainda não foi materializado.

## Open warnings

- `Organizations.Access.authorize/…` ainda não foi implementado;
- `ServiceAccount` ainda não foi materializado;
- AuditEvent para histórico de permission/role assignment ainda não foi materializado;
- mecanismo físico de inclusão de `packages/` no build ainda não foi ratificado;
- JSON Schema definitivo de `manifest.json` ainda não foi fechado;
- mecanismo físico de durable cross-context facts/outbox ainda não foi fechado;
- mecanismo concreto de historical deployment state ainda não foi fechado;
- cliente HTTP e pool strategy ainda não foram escolhidos;
- endpoints, schemas, tabelas, campos e índices de outros contexts ainda não estão congelados.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/architecture/modelo-conceitual.md`
- `docs/architecture/runtime-otp-broadway.md`
- `docs/architecture/ambientes-rbac-homologacao.md`
- `docs/architecture/observabilidade-e-auditoria.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`
