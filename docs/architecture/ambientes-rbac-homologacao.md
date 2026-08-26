# Ambientes, RBAC e homologação

## Environment

Environment é um escopo operacional dentro de uma Organization.

Nomes não precisam ser hardcoded, mas exemplos comuns são:

```text
development
homologation
production
```

## Isolamento

Environment separa:

- Connections e Secrets;
- Integration configuration;
- Deployments;
- Runs e history;
- IdentityMappings;
- schedules;
- access permissions.

Nunca usar credencial de teste como fallback em produção.

## Promotion

Package Versions são imutáveis.

```text
Package 1.4.0
    ↓ deploy HML
homologation Runs
    ↓ approval
promote
    ↓
PROD deployment uses 1.4.0
with PROD Connections and config
```

Promoção não copia secrets.

## Rollback

Rollback seleciona uma Package Version anterior e gera AuditEvent. Runs antigos continuam referenciando seus snapshots originais.

## Homologation

Homologação deve registrar:

- Package Version testada;
- environment de origem;
- test Runs/evidências;
- approver;
- timestamps;
- resultado;
- observações;
- target environment.

Dry-run e payloads anonimizados podem entrar em releases posteriores.

## RBAC

Permissões são a primitive; Roles são agrupamentos.

Dimensões:

```text
who
→ User or ServiceAccount

what
→ Permission

where
→ Organization + Environment
```

Exemplos:

```text
integration.read
integration.write
integration.run
integration.approve
integration.promote
run.cancel
run.retry
connection.read_metadata
secret.rotate
payload.read
audit.read
environment.manage
```

Acesso a status pode ser separado de acesso a payloads sensíveis.

### Role assignments

A atribuição inicial de Role para usuários acontece através de `Membership`:

```text
Membership
└── RoleAssignment
    ├── role_id
    └── environment_id | nil
```

Semântica do scope:

```text
environment_id == nil
→ Role vale para toda a Organization do Membership

environment_id != nil
→ Role vale somente naquele Environment
```

`RoleAssignment` representa estado corrente de autorização e não possui identidade
de domínio própria nem lifecycle separado.

```text
assign_role
→ INSERT

revoke_role
→ DELETE

histórico
→ AuditEvent
```

Invariantes para criação de assignment:

- Organization do Membership deve existir e estar ativa;
- Membership deve existir e estar ativo;
- Role deve existir, estar ativo e pertencer à mesma Organization;
- Environment, quando informado, deve existir, estar ativo e pertencer à mesma Organization;
- o mesmo Role pode coexistir em scope organization-wide e em scopes de Environment;
- o mesmo Role não pode ser duplicado dentro do mesmo scope para o mesmo Membership.

Revogação é idempotente e pode reduzir acesso mesmo quando recursos relacionados já
estão desabilitados.

## Autorização

Controllers/plugs fazem checagem na borda, mas operações de domínio privilegiadas também devem exigir actor/scope explícitos. Não depender somente de `require_admin` no controller.
