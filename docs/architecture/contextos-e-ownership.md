# Contextos e ownership

> **Status: RATIFICADO APÓS REVISÃO CONJUNTA.** Este documento descreve o Context Map consolidado do Leafcutter. As boundaries abaixo substituem as dependências propostas durante a primeira rodada individual.

## Regra estrutural

Cada context pode expor:

```text
root facade
→ operações sobre o conceito principal

capability modules
→ grupos coerentes de operações públicas

internal modules
→ implementação não consumida por outros contexts
```

Ownership conceitual não implica automaticamente:

```text
uma tabela
um módulo dedicado
um processo OTP
um supervisor próprio
```

Schemas, queries e regras de negócio pertencem ao context que controla aquele dado.

Outros contexts não acessam internals diretamente.

## Regra de dependência entre contexts

Após a revisão conjunta, os sete contexts de domínio possuem **zero dependências diretas entre si**:

```text
Organizations   → none
Catalog         → none
Connections     → none
Integrations    → none
Executions      → none
Notifications   → none
Audit           → none
```

Isso não impede entidades de carregarem referências como:

```text
organization_id
environment_id
package_id
connection_id
integration_id
```

Também não decide antecipadamente se haverá foreign keys físicas entre tabelas.

Uma referência por ID não cria dependência de API entre contexts.

## Composição cross-context

Use cases que precisam combinar mais de um context são coordenados por **application workflow modules** dentro da OTP application que possui aquele use case.

Exemplos:

```text
leafcutter_core workflow
→ Catalog + Connections + Integrations

leafcutter_runtime workflow
→ Integrations + Connections + Executions + connector runtime

leafcutter_api
→ autentica / autoriza / adapta HTTP
→ chama workflow ou API pública
```

Não criar por antecipação:

```text
ApplicationService
WorkflowEngine
CommandBus
CrossContextService
```

## Autorização

A autorização ocorre na application/API boundary antes de operações privilegiadas.

```text
request
→ Organizations.Access.authorize(...)
→ domain workflow / context API
```

Jobs e runtime internos podem operar como system execution confiável, mantendo scopes e invariantes explícitos.

Contexts não dependem de `Organizations` apenas para repetir autorização.

---

# 1. Organizations

> **Status: RATIFICADO**

## Responsabilidade

```text
tenancy
+
operational scope
+
authorization
```

## Owns

- `Organization`;
- `Environment`;
- `User`;
- `ServiceAccount`;
- `Membership`;
- `Role`;
- `Permission`;
- access grants e assignments.

`Environment` pertence a `Organizations` e seus nomes não são hardcoded.

`User` e `ServiceAccount` são atores do domínio e sujeitos de autorização.

Mecanismos concretos de autenticação ficam fora desta boundary inicialmente:

```text
passwords
sessions
OIDC / OAuth login
MFA
login attempts
```

Não criar `Authentication` ou `Accounts` apenas por antecipação.

## RBAC

`Permission` é a primitive fundamental e pode começar como identifiers conhecidos em código, por exemplo:

```text
integration.read
integration.write
run.cancel
```

`Role` agrupa permissions.

Não assumir que `Permission` precisa de tabela própria.

## Public surface inicial

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

Operações conceituais:

```elixir
Organizations.create(...)
Organizations.get(...)
Organizations.disable(...)

Organizations.Environments.create(...)
Organizations.Environments.get(...)
Organizations.Environments.disable(...)

Organizations.Access.add_member(...)
Organizations.Access.remove_member(...)
Organizations.Access.assign_role(...)
Organizations.Access.revoke_role(...)
Organizations.Access.authorize(...)
```

As assinaturas concretas ainda não estão congeladas.

## Dependências de domínio

```text
none
```

## OTP

Não possui processos OTP próprios inicialmente.

Não criar `Organizations.Supervisor` vazio.

---

# 2. Catalog

> **Status: RATIFICADO**

## Responsabilidade

Registrar, versionar, publicar, disponibilizar e permitir descoberta de building blocks reutilizáveis.

Catalog controla identidade, metadata, versões e disponibilidade.

Ele **não executa** os artefatos registrados.

## Owns

### Connectors

- Connector metadata;
- `ConnectorVersion`;
- Operation metadata;
- publication / availability metadata.

`Operation` pertence a uma `ConnectorVersion`.

Não existe `OperationVersion` inicialmente.

A implementação executável permanece em `leafcutter_connectors`.

### Contracts

- `Contract`;
- `ContractVersion`.

### Integration Packages

- `Package`;
- `PackageVersion`;
- publication / availability metadata.

`PackageDependency` foi removido do V1 por YAGNI.

Categorias são apenas metadata de classificação e descoberta. Não existe `CatalogCategory` como entidade inicial.

## Imutabilidade

Versões publicadas são imutáveis:

```text
PackageVersion
ConnectorVersion
ContractVersion
```

Antes da publicação o artefato está sendo preparado. Publicar cria a versão canônica imutável.

Não criar draft-state model antecipadamente.

## PackageVersion

Uma `PackageVersion` fixa a definição executável reutilizável:

```text
exactly 1 Source
→ 1..N Destinations
```

Ela referencia explicitamente:

- `ConnectorVersion` + Operation para source e destinations;
- `ContractVersion` para source e destinations;
- regra de `SourceIdentity`;
- transformations;
- enrichment definitions;
- interceptor declarations;
- topology e config contract.

A regra de `SourceIdentity` pertence à definição de Source da `PackageVersion` e não vira `IdentityRule` entity.

Novas versões de contracts/connectors não alteram uma `PackageVersion` já publicada.

## Escopo

Catalog pode possuir artefatos:

```text
platform-wide official
organization-scoped private
```

`organization_id` neste caso é scope reference, não dependência de `Organizations`.

## Public surface inicial

```text
Catalog.Packages
Catalog.Contracts
Catalog.Connectors
```

Operações conceituais:

```elixir
Catalog.Packages.register(...)
Catalog.Packages.publish_version(...)
Catalog.Packages.get_version(...)

Catalog.Contracts.register(...)
Catalog.Contracts.publish_version(...)
Catalog.Contracts.get_version(...)

Catalog.Connectors.register(...)
Catalog.Connectors.publish_version(...)
Catalog.Connectors.get_operation(...)
```

Compile/validate de JSON Schema não pertence à API pública ratificada de `Catalog.Contracts` neste momento.

## Dependências de domínio

```text
none
```

## OTP

Não possui processos OTP próprios inicialmente.

---

# 3. Connections

> **Status: RATIFICADO**

## Responsabilidade

Representar, configurar e resolver o acesso de `Organization + Environment` a sistemas externos.

## Owns

- `Connection`;
- `Secret`;
- `SecretVersion`;
- authentication configuration;
- OAuth token / refresh durable state;
- secret rotation metadata.

## Connection

`Connection` contém configuração não sensível, por exemplo:

```text
connector identity
base URL
account identifier
region
timeouts
auth scheme configuration
secret reference
```

Uma Connection referencia **Connector identity**, não `ConnectorVersion`.

A `PackageVersion` é quem fixa qual `ConnectorVersion + Operation` será executado.

Isso permite atualizar implementação de connector sem recriar credenciais/configuração da Connection.

## Secret

`SecretVersion` permite versionamento e rotação.

Raw secret values não devem aparecer em:

```text
PackageVersion
RunSnapshot público
logs
ExecutionEvent
AuditEvent
API response
```

OAuth durable state pertence aqui.

## Escopo

```text
Organization
└── Environment
    └── Connection
```

Connection persiste scope refs e stable connector identity sem depender das APIs de `Organizations` ou `Catalog`.

A application layer pode resolver/validar descriptors externos antes de criar ou alterar a Connection.

## Public surface inicial

```text
Connections
└── Connections.Secrets
```

Operações conceituais:

```elixir
Connections.create(...)
Connections.get(...)
Connections.disable(...)
Connections.resolve(...)

Connections.Secrets.rotate(...)
Connections.Secrets.resolve_for_runtime(...)
```

## Dependências de domínio

```text
none
```

## OTP

Não possui processos OTP próprios inicialmente.

Um processo coordenado de OAuth refresh/cache só deve surgir quando houver lifecycle real que o justifique.

---

# 4. Integrations

> **Status: RATIFICADO**

## Responsabilidade

Representar a integração lógica de uma Organization e sua configuração executável em cada Environment.

## Distinção fundamental

```text
Package
→ identidade reutilizável

PackageVersion
→ definição executável versionada

Integration
→ identidade lógica dentro da Organization

EnvironmentDeployment
→ configuração executável para um Environment

Run
→ execução concreta
```

## Integration

`Integration` pertence a uma `Organization` e possui uma associação estável a um `Package`.

Ela **não** pertence diretamente a um único Environment.

Mudar para um Package semanticamente diferente implica criar outra Integration.

Labels pertencem à Integration e são compartilhadas entre seus environments.

## EnvironmentDeployment

Existe exatamente um deployment lógico corrente por:

```text
Integration + Environment
```

Ele contém a configuração executável environment-specific:

- Environment reference;
- `PackageVersion` da mesma Package da Integration;
- uma Source Connection binding;
- N Destination Connection bindings;
- promotable config;
- environment-local config;
- Triggers;
- active/disabled lifecycle.

Diferentes environments podem executar diferentes `PackageVersion`s da mesma Integration.

Exemplo:

```text
homologation → PackageVersion 1.5
production   → PackageVersion 1.4
```

## Binding compatibility

A `PackageVersion` declara o Connector esperado para cada slot.

O deployment recebe descriptors resolvidos pela application layer e valida que cada Connection binding pertence ao Connector identity compatível.

`Integrations` não consulta diretamente `Catalog` ou `Connections` para realizar essa validação.

## Configuração

Separação obrigatória:

```text
promotable config
→ configuração funcional/business aprovada e promovível

environment-local config
→ bindings, triggers, endpoints e overrides operacionais locais
```

Promotion nunca sobrescreve local config do target.

## Triggers

`Schedule` não é uma entidade independente.

`Trigger` pode ter tipos como:

```text
manual
schedule / cron
inbound/event later
```

Triggers pertencem ao `EnvironmentDeployment` e são environment-local.

## Homologation

`HomologationRequest` aprova uma **state fingerprint imutável** do deployment.

Qualquer mudança relevante após aprovação invalida aquela aprovação para promoção.

Runs podem ser referenciados como evidence por IDs opacos; `Integrations` não consulta `Executions` para interpretá-los.

## Promotion

Promotion carrega para o target somente o estado promovível aprovado:

```text
PackageVersion
+
promotable config
+
homologation fingerprint/reference
```

Nunca copia:

```text
Connection bindings
Secrets
credentials
Triggers
environment-local config
```

O target usa suas próprias Connections compatíveis.

Promotion pode permanecer como registro histórico.

## Rollback

Rollback é **operação**, não entidade inicial.

Ele seleciona um estado promovido anterior válido do target deployment e preserva local config/connections do próprio target.

Não criaremos `Rollback` record no V1.

## Histórico do deployment

Ainda não foi ratificada uma entidade `DeploymentRevision`.

O requisito, porém, está fechado: mudanças relevantes precisam preservar estado histórico suficiente para reconstruir estados promovidos anteriores e suportar homologation/promotion/rollback.

O mecanismo físico será decidido quando modelarmos persistência.

## IdentityMapping

`IdentityMapping` pertence a `Integrations` porque persiste entre Runs.

Scope conceitual:

```text
EnvironmentDeployment + Destination
```

Ele representa associação cross-system reutilizável.

A `Delivery` registra separadamente a destination identity observada naquela execução específica.

## Public surface inicial

```text
Integrations
├── Integrations.Destinations
├── Integrations.Triggers
├── Integrations.Deployments
├── Integrations.Homologations
└── Integrations.IdentityMappings
```

Operações conceituais importantes:

```elixir
Integrations.create(...)
Integrations.get(...)

Integrations.Deployments.get_execution_definition(...)
Integrations.Deployments.activate(...)
Integrations.Deployments.disable(...)
Integrations.Deployments.promote(...)
Integrations.Deployments.rollback(...)

Integrations.Homologations.approve(...)
Integrations.Homologations.reject(...)

Integrations.IdentityMappings.resolve(...)
Integrations.IdentityMappings.upsert(...)
```

Activation/disable pertence ao deployment, não à Integration lógica.

## Dependências de domínio

```text
none
```

## OTP

Não possui processos OTP próprios inicialmente.

Scheduling durável pode utilizar Oban via infraestrutura compartilhada quando apropriado.

---

# 5. Executions

> **Status: RATIFICADO**

## Responsabilidade

Transformar uma definição executável já resolvida em execução concreta, durável e recuperável.

## Owns

- `Run`;
- `RunSnapshot`;
- `Record`;
- `Delivery`;
- `Attempt`;
- Enrichment execution result/status;
- `Checkpoint`;
- `ExecutionEvent`;
- durable ownership/fencing/recovery state como `owner_node` e `generation`.

A **definição** de Enrichment pertence à `PackageVersion`; `Executions` possui apenas estado/resultados da execução.

## Run e RunSnapshot

Um Run nasce de um `EnvironmentDeployment`.

A application/runtime layer resolve a definição externa e entrega a `Executions` os dados necessários para criar:

```text
Run
+
RunSnapshot
```

O snapshot congela referências lógicas relevantes, incluindo:

- PackageVersion;
- ContractVersions;
- effective config;
- Connection IDs;
- applicable SecretVersion IDs/references.

Raw secret values não são congelados no snapshot.

OAuth token refresh continua sendo operacionalmente resolvido por `Connections`.

## Record

`Record` representa uma ocorrência source dentro do Run.

Ele carrega:

```text
SourceIdentity
PayloadHash
```

Nenhum dos dois é o ID do Record e nenhum precisa de entity própria.

## Delivery

Uma `Delivery` é a responsabilidade durável de processar um Record para um destination.

Ela registra a destination identity observada nessa execução.

## Attempt

`Attempt` é uma tentativa concreta de chamada externa.

Semântica base:

```text
at-least-once
```

Não existe promessa universal de exactly-once.

## Checkpoint

Checkpoint representa progresso durável e seguro do source.

A persistência do checkpoint deve ser coordenada com o durable fan-out para impedir avanço sem representação durável do trabalho produzido.

## ExecutionEvent

`ExecutionEvent` registra lifecycle da execução.

Ele **não** é o event bus genérico da plataforma e não deve ser reutilizado como outbox cross-context.

## Runtime OTP não pertence ao Context

A infraestrutura OTP abaixo pertence à application `leafcutter_runtime`, e não ao ownership conceitual de `Executions`:

```text
Registry
Run DynamicSupervisor
NodeHeartbeat
RunCoordinator
SourceBroadway
optional EnrichmentBroadway
DestinationBroadway x N
```

Isso separa domínio durável de infraestrutura operacional.

## Dependências de domínio

```text
none
```

A composição para iniciar um Run ocorre no workflow da runtime application:

```text
resolve EnvironmentDeployment
→ resolve Connections / SecretVersion refs
→ create Run + RunSnapshot in Executions
→ start Run supervision subtree
```

---

# 6. Notifications

> **Status: RATIFICADO**

## Responsabilidade

Transformar fatos duráveis relevantes em entregas de notificação para recipients configurados.

## Owns

- `NotificationRule`;
- `Recipient`;
- `NotificationDelivery`.

`NotificationChannel` foi removido como entity.

Channel é parte do tipo/config do Recipient, por exemplo:

```text
email
slack
webhook
```

`Recipient` é independente de `User` inicialmente.

## NotificationDelivery

Retry state fica diretamente na delivery:

```text
status
attempt_count
available_at
last_error
delivered_at
```

Não criar `NotificationAttempt` inicialmente.

Durabilidade inicial:

```text
NotificationDelivery
+
PostgreSQL
+
Oban
```

## Consumo de fatos

Rules recebem um envelope self-contained de fato durável.

Notifications não deve consultar internals do context produtor para completar o fato.

## Public surface inicial

```text
Notifications.Rules
Notifications.Recipients
Notifications.deliver_for_event(...)
```

## Dependências de domínio

```text
none
```

## OTP

Não possui processos OTP próprios inicialmente.

---

# 7. Audit

> **Status: RATIFICADO**

## Responsabilidade

Registrar de forma durável e consultável ações humanas e administrativas relevantes.

## Owns

- `AuditEvent`;
- actor metadata;
- action;
- target reference;
- organization/environment scope refs;
- redacted change metadata.

## Imutabilidade

`AuditEvent` é append-only e imutável.

Correções ou reversões geram um novo event.

Raw secrets não podem ser persistidos no Audit.

## Sink

Audit é sink.

Nenhum outro context consulta Audit para tomar decisões de negócio.

## Public surface inicial

```elixir
Audit.record(...)
Audit.list(...)
```

Não criar capability modules sem necessidade real.

## Dependências de domínio

```text
none
```

## OTP

Não possui processos OTP próprios inicialmente.

---

# Fatos duráveis cross-context

Notifications e Audit não devem depender de chamadas diretas obrigatórias feitas depois que uma transação de domínio já foi concluída.

Quando entregar um fato a outro context é uma obrigação do sistema, o fato deve ser persistido de forma durável **na mesma transação** que altera o estado causador.

Envelope conceitual:

```json
{
  "type": "run.failed",
  "organization_id": "...",
  "environment_id": "...",
  "occurred_at": "...",
  "actor": {},
  "target": {"type": "run", "id": "..."},
  "data": {"integration_id": "...", "run_id": "..."}
}
```

O envelope deve carregar contexto suficiente para o consumer não consultar o producer.

Não criar um context `Events` ou `Outbox`.

Outbox é um mecanismo de infraestrutura/integration concern. A representação física ainda será decidida quando a persistência for modelada.

---

# Context Map final

```text
Organizations   → none
Catalog         → none
Connections     → none
Integrations    → none
Executions      → none
Notifications   → none
Audit           → none
```

As relações entre conceitos continuam existindo por referências explícitas, enquanto workflows cross-context são compostos na application layer.

Esse isolamento é intencional: reduz acoplamento de domínio sem introduzir microservices, buses ou abstrações genéricas antecipadas.
