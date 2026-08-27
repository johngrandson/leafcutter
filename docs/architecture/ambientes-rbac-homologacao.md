# Ambientes, RBAC e homologação

> **Status: RBAC MATERIALIZADO; HOMOLOGAÇÃO/PROMOÇÃO RATIFICADAS — NÃO MATERIALIZADAS.**

## Environment atual

`Environment` é um scope operacional configurável dentro de uma Organization. Nomes como `development`, `homologation` e `production` são convenções, não valores hardcoded.

Lifecycle básico de Environment está implementado. Novos recursos não são criados em Organization ou Environment desabilitado quando a operação exige scope ativo.

## RBAC materializado

### Atores

```text
User
└── Membership in Organization

ServiceAccount
└── direct Organization ownership
```

Não existe `Principal` persistido.

### Roles e permissions

`Role` é organization-scoped. `Permission` é primitive conhecida em código e persistida por identifier estável.

Catálogo materializado hoje:

```text
organization.read
organization.manage
environment.read
environment.manage
access.manage
```

A expansão para permissions como `integration.run`, `run.cancel`, `secret.rotate` e `payload.read` é futura e acontecerá junto às capacidades correspondentes.

### Assignments

```text
Membership
└── RoleAssignment

ServiceAccount
└── ServiceAccountRoleAssignment
```

Scope:

```text
environment_id == nil
→ organization-wide

environment_id != nil
→ exact Environment
```

Assignment organization-wide satisfaz checks em qualquer Environment ativo da mesma Organization. Assignment environment-scoped não satisfaz Organization nem outro Environment.

### Estado corrente

Assignments e RolePermissions representam estado atual:

```text
assign/grant → INSERT
revoke       → DELETE
history      → future AuditEvent
```

Revogações são idempotentes e podem reduzir acesso mesmo com recursos desabilitados.

### API de decisão

```elixir
Organizations.Access.authorize(actor, permission, scope)
```

Actors:

```text
{:user, user_id}
{:service_account, service_account_id}
```

Scopes:

```text
{:organization, organization_id}
{:environment, environment_id}
```

A decisão valida lifecycle do actor, membership/ownership, Organization, Environment, Role e Permission. Ausência de grant aplicável retorna `:permission_denied`.

## Segurança futura

Ainda não materializado:

- credenciais concretas de ServiceAccount;
- passwords/sessions/OIDC/MFA para User;
- payload access permissions;
- secret rotation;
- AuditEvent de mudanças de RBAC;
- policy de exposição de erros na API HTTP.

## Homologação ratificada

Planejado:

```text
EnvironmentDeployment state
→ immutable fingerprint
→ HomologationRequest approval
→ promote approved promotable state
```

Promotion copiará somente:

```text
PackageVersion
promotable config
approval/fingerprint reference
```

Não copiará:

```text
Connections
Secrets
Triggers
environment-local config
```

## Rollback ratificado

Rollback será operação que seleciona estado promovido anterior válido. Não haverá entidade `Rollback` inicial. Runs históricos continuarão ligados aos próprios snapshots.

## Evidências

Runs poderão ser referenciadas por IDs opacos como evidência de homologação. Integrations não dependerá de internals de Executions para interpretar esses IDs.
