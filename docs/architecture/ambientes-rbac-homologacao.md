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

### Service accounts

`ServiceAccount` representa um ator não humano scoped diretamente por uma Organization:

```text
Organization
└── ServiceAccount
    ├── id
    ├── name
    └── disabled_at
```

Diferente de `User`, um `ServiceAccount` não participa de `Membership`.

```text
User
└── Membership

ServiceAccount
└── Organization direta
```

Essa separação mantém FKs e tipos explícitos e evita introduzir antecipadamente um
`Principal` polimórfico ou transformar `Membership` em uma abstração genérica de ator.

Credenciais concretas não pertencem ao schema de `ServiceAccount` inicialmente:

```text
API key
token
client secret
authentication mechanism
```

Esses mecanismos serão modelados apenas quando a autenticação concreta de service
accounts for implementada.

Criação de `ServiceAccount` exige Organization existente e ativa. Disable é idempotente
e permanece permitido mesmo se a Organization já estiver desabilitada.

### Role assignments para User

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

Invariantes para criação de assignment:

- Organization do Membership deve existir e estar ativa;
- Membership deve existir e estar ativo;
- Role deve existir, estar ativo e pertencer à mesma Organization;
- Environment, quando informado, deve existir, estar ativo e pertencer à mesma Organization;
- o mesmo Role pode coexistir em scope organization-wide e em scopes de Environment;
- o mesmo Role não pode ser duplicado dentro do mesmo scope para o mesmo Membership.

### Role assignments para ServiceAccount

`ServiceAccount` recebe Roles sem passar por `Membership`:

```text
ServiceAccount
└── ServiceAccountRoleAssignment
    ├── role_id
    └── environment_id | nil
```

A semântica de scope é a mesma do usuário:

```text
environment_id == nil
→ Role vale para toda a Organization do ServiceAccount

environment_id != nil
→ Role vale somente naquele Environment
```

`ServiceAccountRoleAssignment` representa estado corrente de autorização, não possui
identidade de domínio própria e permanece separado de `RoleAssignment`.

Invariantes para criação:

- Organization do ServiceAccount deve existir e estar ativa;
- ServiceAccount deve existir e estar ativo;
- Role deve existir, estar ativo e pertencer à mesma Organization;
- Environment, quando informado, deve existir, estar ativo e pertencer à mesma Organization;
- o mesmo Role pode coexistir em scope organization-wide e em scopes de Environment;
- o mesmo Role não pode ser duplicado dentro do mesmo scope para o mesmo ServiceAccount.

Para ambos os tipos de assignment:

```text
assign_role
→ INSERT

revoke_role
→ DELETE

histórico
→ AuditEvent
```

Revogação é idempotente e pode reduzir acesso mesmo quando recursos relacionados já
estão desabilitados.

A separação física entre `RoleAssignment` e `ServiceAccountRoleAssignment` é
intencional: preserva FKs e tipos explícitos sem introduzir um `Principal` polimórfico.

## Autorização

Controllers/plugs fazem checagem na borda, mas operações de domínio privilegiadas também devem exigir actor/scope explícitos. Não depender somente de `require_admin` no controller.
