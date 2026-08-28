# Contextos e ownership

> **Status: CONTEXT MAP RATIFICADO; MATERIALIZAÇÃO PARCIAL.** Os sete contexts permanecem independentes. A tabela abaixo informa o estado real de cada um.

## Regra estrutural

```text
root facade
→ operações sobre o conceito principal

capability modules
→ grupos coerentes de operações públicas

internal modules
→ schemas, queries e implementação privada
```

Ownership não implica tabela, módulo ou processo próprio. Outros contexts não acessam internals.

## Dependências de domínio

```text
Organizations   → none
Catalog         → none
Connections     → none
Integrations    → none
Executions      → none
Notifications   → none
Audit           → none
```

Referências por ID não criam dependência de API. Workflows cross-context pertencem à OTP application que possui o use case.

## Estado de materialização

| Context | Estado | Materializado | Preservado para o futuro |
|---|---|---|---|
| Organizations | MATERIALIZADO | tenancy, Environment, User, ServiceAccount, Membership, Role, permissions, assignments, authorize | autenticação concreta e matriz ampliada |
| Catalog | RATIFICADO — NÃO MATERIALIZADO | — | connectors, contracts, packages e versões publicadas |
| Connections | RATIFICADO — NÃO MATERIALIZADO | — | Connection, Secret, SecretVersion, OAuth state |
| Integrations | RATIFICADO — NÃO MATERIALIZADO | — | Integration, EnvironmentDeployment, promotion, homologation, IdentityMapping |
| Executions | PARCIALMENTE MATERIALIZADO | RuntimeNode, Run, RunSnapshot, criação atômica, ownership, fencing, recovery | Record, Delivery, Attempt, Checkpoint, ExecutionEvent |
| Notifications | RATIFICADO — NÃO MATERIALIZADO | Oban compartilhado como infraestrutura | rules, recipients e durable deliveries |
| Audit | RATIFICADO — NÃO MATERIALIZADO | — | append-only AuditEvent |

## Organizations

Owns:

```text
Organization
Environment
User
ServiceAccount
Membership
Role
Permission
RoleAssignment
ServiceAccountRoleAssignment
```

Autorização ocorre na boundary da aplicação/API:

```text
request or workflow
→ Organizations.Access.authorize(actor, permission, scope)
→ privileged operation
```

Não existe `Principal` persistido. User recebe Role por Membership; ServiceAccount pertence diretamente à Organization.

## Catalog

O modelo mínimo e suas APIs foram ratificados no ADR-0018, ainda sem implementação. Owns:

```text
Connector metadata + ConnectorVersion
Operation metadata
Contract + ContractVersion
Package + PackageVersion
publication and availability
```

Operation pertence a ConnectorVersion. Não existe OperationVersion inicial. O primeiro slice publica versões e filhos atomicamente, usa endpoints relacionais de PackageVersion e protege conteúdo versionado contra alteração.

## Connections

O modelo mínimo e suas APIs foram ratificados no ADR-0018, ainda sem implementação. Owns:

```text
Connection
Secret
SecretVersion
OAuth durable state
rotation metadata
```

Connection referencia Connector identity, não ConnectorVersion. Connection é environment-scoped, mantém config não sensível e pode apontar explicitamente para uma SecretVersion imutável. Raw secret storage continua fora do slice.

## Integrations

O modelo mínimo e suas APIs foram ratificados no ADR-0018, ainda sem implementação. Owns:

```text
Integration
EnvironmentDeployment
Trigger
HomologationRequest
Promotion history
IdentityMapping
```

Integration é lógica, organization-scoped e ligada a Package estável. EnvironmentDeployment contém PackageVersion, promotable/local config e bindings locais de Connection. O resolver transacional pertence a leafcutter_runtime.

## Executions

Owns hoje:

```text
RuntimeNode
Run
RunSnapshot
ownership/fencing/recovery state
```

Owns futuramente:

```text
Record
Delivery
Attempt
Enrichment execution result
Checkpoint
ExecutionEvent
```

Runtime OTP infrastructure — Registry, supervisors, heartbeat, recovery e Broadway — pertence à application `leafcutter_runtime`, não ao ownership conceitual do context.

## Notifications

Owns futuramente:

```text
NotificationRule
Recipient
NotificationDelivery
```

Delivery de notificação terá retry state próprio e poderá usar Oban. Não criar NotificationAttempt inicialmente.

## Audit

Owns futuramente `AuditEvent`, append-only e imutável. Audit é sink e não participa de decisão de negócio.

## Fatos duráveis cross-context

Quando entregar um fato é obrigação do sistema, ele deve ser persistido atomicamente com a mudança causadora. O envelope precisa ser self-contained.

Não criar um context `Events` nem um event bus genérico. O mecanismo físico ainda está aberto.

## Composição por application

```text
leafcutter_core workflow
→ compõe APIs públicas de contexts hospedados em core

leafcutter_runtime workflow
→ resolve definição externa, cria Executions state e inicia runtime

leafcutter_api
→ autentica, autoriza, adapta HTTP e chama APIs públicas
```

Não criar `ApplicationService`, `CommandBus` ou `WorkflowEngine` genéricos por antecipação.
