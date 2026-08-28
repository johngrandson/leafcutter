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
| Catalog | PARCIALMENTE MATERIALIZADO | Connector, ConnectorVersion, Operation, Contract, ContractVersion, Package, PackageVersion e endpoints | availability, manifest e build |
| Connections | MATERIALIZADO — SLICE MÍNIMO | Connection, Secret, SecretVersion e lifecycle/config binding | OAuth state, providers, rotation e retention |
| Integrations | MATERIALIZADO — SLICE MÍNIMO | Integration, EnvironmentDeployment, bindings e lifecycle mínimo | promotion, homologation, Triggers, IdentityMapping |
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

O modelo mínimo e suas APIs foram ratificados no ADR-0018 e estão materializados. Owns:

```text
Connector metadata + ConnectorVersion
Operation metadata
Contract + ContractVersion
Package + PackageVersion
publication and availability
```

Operation pertence a ConnectorVersion. Não existe OperationVersion inicial. ConnectorVersion e Operations são publicados atomicamente e protegidos contra append, update e delete após o sealing. ContractVersion materializa uma identidade publicada e imutável. PackageVersion publica atomicamente uma source e destinations ordenadas, pinando Operation e ContractVersion em endpoints relacionais igualmente imutáveis.

## Connections

O modelo mínimo e suas APIs ratificados no ADR-0018 estão materializados. Owns:

```text
Connection
Secret
SecretVersion
mutable config and exact binding lifecycle
```

Connection referencia Connector identity, não ConnectorVersion. Connection e Secret possuem scope explícito de Organization/Environment; SecretVersion herda esse scope de Secret. Config é não sensível e o binding opcional seleciona uma versão exata. A boundary pública valida parents ativos com locks compartilhados e expõe leitura batch das SecretVersions exatas por scope, enquanto o PostgreSQL protege scope, JSON object, binding compatível e imutabilidade de SecretVersion.

Continuam futuros OAuth durable state, providers/encryption, rotation, revocation e retention. Raw secret storage permanece fora do slice.

## Integrations

O modelo mínimo e suas APIs foram ratificados no ADR-0018 e estão materializados. Owns:

```text
Integration
EnvironmentDeployment
Trigger
HomologationRequest
Promotion history
IdentityMapping
```

Integration é lógica, organization-scoped e ligada a Package estável. A facade pública cria, lê, desabilita e oferece o lock ativo exigido por workflows compostos. `Integrations.Deployments` cria, lê, substitui atomicamente e bloqueia para resolução um EnvironmentDeployment completo por Integration/Environment, incluindo PackageVersion, promotable/local config e todos os bindings locais de Connection. A capability também expõe uma descoberta restrita aos parent IDs imutáveis para ordenar locks sem antecipar a leitura dos bindings. O resolver transacional está materializado em `leafcutter_runtime`.

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

O workflow `LeafcutterRuntime.Runs.create_from_deployment/1` também pertence a essa application: compõe somente APIs públicas de Organizations, Catalog, Connections, Integrations e Executions sem mover ownership entre contexts.

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
