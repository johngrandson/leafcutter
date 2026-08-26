# Contextos e ownership

> **Status: CONTEXT MAP RATIFICADO.** Todos os contexts propostos passaram pela primeira rodada de ratificação individual. O próximo passo é revisar o mapa completo em conjunto antes de definir as boundaries das OTP applications.

## Regra estrutural

Cada context possui:

```text
root facade
→ operações sobre o conceito principal

capability modules
→ grupos coerentes de operações públicas

internal modules
→ implementação não consumida por outros contexts
```

Schemas e queries pertencem ao context que controla o dado.

Outros contexts utilizam somente APIs públicas.

Ownership conceitual não implica automaticamente:

```text
uma tabela
um módulo dedicado
um processo OTP
um supervisor próprio
```

Toda OTP application do Leafcutter deve possuir árvore de supervisão desde sua criação.

Um context recebe uma subtree própria quando possuir processos com lifecycle, estado temporal, concorrência, coordenação ou isolamento de falha que justifiquem isso.

---

# 1. Organizations

> **Status: RATIFICADO**

## Responsabilidade

`Organizations` é responsável por:

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

## Environment

`Environment` representa uma subdivisão operacional de uma Organization.

```text
Organization
├── development
├── homologation
└── production
```

Os nomes não são necessariamente hardcoded.

Outros contexts podem possuir recursos scoped por Environment sem que esses recursos passem a pertencer a `Organizations`.

## Atores

`User` e `ServiceAccount` pertencem ao context como atores do domínio e sujeitos de autorização.

`Membership` representa a relação entre um ator e uma Organization.

Mecanismos concretos de autenticação ficam fora dessa boundary.

Exemplos:

```text
password management
login sessions
OAuth/OIDC login
MFA
authentication refresh tokens
login attempts
```

Não criar `Authentication` ou `Accounts` como context apenas por antecipação.

## RBAC

RBAC pertence a `Organizations`.

```text
who
→ User | ServiceAccount

what
→ Permission

where
→ Organization + optional Environment
```

`Permission` é a primitive fundamental.

`Role` agrupa permissions.

Grants e assignments associam atores às permissões disponíveis em determinado scope.

## Public surface

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

Facade:

```elixir
Organizations.create(...)
Organizations.get(...)
Organizations.disable(...)
```

Environments:

```elixir
Organizations.Environments.create(...)
Organizations.Environments.get(...)
Organizations.Environments.disable(...)
```

Access:

```elixir
Organizations.Access.add_member(...)
Organizations.Access.remove_member(...)
Organizations.Access.assign_role(...)
Organizations.Access.revoke_role(...)
Organizations.Access.authorize(...)
```

As assinaturas ainda não estão congeladas.

## Dependências

```text
Organizations
→ nenhuma dependência de domínio
```

`Organizations` é uma boundary de fundação.

## OTP e supervisão

Não possui necessidade atual de processos OTP próprios.

O app que hospedar `Organizations` será supervisionado desde sua criação.

Não criar um `Organizations.Supervisor` vazio.

## Não pertence aqui

- mecanismos concretos de autenticação;
- Package;
- Connection;
- Secret;
- Integration;
- Run;
- Record;
- Delivery;
- Attempt;
- Notification;
- AuditEvent.

---

# 2. Catalog

> **Status: RATIFICADO**

## Responsabilidade

`Catalog` é responsável por:

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

Ele controla identidade, metadata, versões e disponibilidade.

Ele não executa os artefatos registrados.

## Owns

### Connectors

- Connector metadata;
- Operation metadata;
- Connector versions;
- publication metadata;
- availability metadata.

A implementação executável permanece fora do Catalog.

```text
Catalog
→ identidade e metadata

Connector implementation
→ código executável
```

### Contracts

- `Contract`;
- `ContractVersion`.

O Catalog registra e versiona contratos.

Consumers utilizam versões explícitas e imutáveis.

### Integration Packages

- `Package`;
- `PackageVersion`;
- `PackageDependency`;
- publication metadata;
- availability metadata.

O código do Package permanece fora do Catalog, inicialmente em:

```text
packages/
```

### Categories

- `CatalogCategory`.

Categorias são metadata de descoberta e classificação.

Não possuem efeito sobre execução.

## Escopo

O Catalog suporta:

```text
platform-wide
→ artefatos oficiais

organization-scoped
→ artefatos privados
```

Não existem dois Catalogs separados.

## Public surface

```text
Catalog
├── Catalog.Packages
├── Catalog.Contracts
└── Catalog.Connectors
```

Packages:

```elixir
Catalog.Packages.register(...)
Catalog.Packages.publish_version(...)
Catalog.Packages.get_version(...)
```

Contracts:

```elixir
Catalog.Contracts.register(...)
Catalog.Contracts.compile(...)
Catalog.Contracts.validate(...)
```

Connectors:

```elixir
Catalog.Connectors.register(...)
Catalog.Connectors.get_operation(...)
```

As assinaturas ainda não estão congeladas.

## Dependências

```text
Catalog
   ↓
Organizations
```

Essa dependência existe para artefatos privados scoped por Organization.

## OTP e supervisão

Não possui necessidade atual de processos OTP próprios.

O app que hospedar Catalog será supervisionado desde sua criação.

Não criar um `Catalog.Supervisor` vazio.

## Não pertence aqui

- Connector implementation;
- Operation implementation;
- Transport implementation;
- Connection;
- Secret;
- Integration configuration;
- Run;
- Record;
- Delivery;
- Attempt;
- runtime orchestration.

---

# 3. Connections

> **Status: RATIFICADO**

## Responsabilidade

`Connections` representa e resolve o acesso configurado de uma:

```text
Organization
+
Environment
```

a sistemas externos.

Ele responde por:

```text
Como este Environment acessa o sistema?

Qual configuração deve ser usada?

Quais credenciais estão associadas?

Qual SecretVersion deve ser utilizada?
```

`Connections` não executa integrações.

## Owns

- `Connection`;
- `Secret`;
- `SecretVersion`;
- authentication configuration;
- OAuth token state;
- OAuth refresh state;
- secret rotation metadata;
- Organization/Environment scope da Connection.

## Connection

Representa configuração não sensível.

Exemplos:

```text
base URL
account identifier
region
timeouts
Connector reference
authentication scheme configuration
Secret reference
```

## Secret

Representa credenciais sensíveis.

`SecretVersion` permite atualização e rotação.

Secrets não devem aparecer em texto claro em:

```text
Integration Package
RunSnapshot público
logs
ExecutionEvent
AuditEvent
API responses
```

## OAuth

Configuração e estado durável de OAuth pertencem a `Connections`.

Podem incluir:

```text
access token
refresh token
expiration state
refresh metadata
rotation state
```

A estratégia concreta de refresh será definida quando houver necessidade operacional real.

## Escopo

```text
Organization
└── Environment
    └── Connection
```

Connections de ambientes diferentes são independentes.

Não existe fallback automático de credenciais de homologação para produção.

Promoção não copia Secrets.

## Relação com Catalog

Uma Connection referencia um Connector conhecido pelo Catalog.

```text
Connection
→ Connector metadata
→ authentication requirements
```

Não conhece a implementação executável do Connector.

## Public surface

```text
Connections
└── Connections.Secrets
```

Facade:

```elixir
Connections.create(...)
Connections.get(...)
Connections.disable(...)
Connections.resolve(...)
```

Secrets:

```elixir
Connections.Secrets.rotate(...)
Connections.Secrets.resolve_for_runtime(...)
```

Não criar antecipadamente:

```text
Connections.OAuth
Connections.Auth
Connections.SecretServer
```

## Dependências

```text
Connections
   ├──→ Organizations
   └──→ Catalog
```

Todas as interações ocorrem por APIs públicas.

## OTP e supervisão

Não possui necessidade atual de processos OTP próprios.

Pode começar principalmente com:

```text
Ecto
Repo
secret resolution
OAuth state persistence
rotation rules
```

Processos supervisionados podem surgir posteriormente se refresh coordenado, cache vivo ou outro lifecycle real os justificar.

## Não pertence aqui

- Connector implementation;
- Operation implementation;
- Transport implementation;
- Package;
- Integration configuration;
- Run;
- Record;
- Delivery;
- Attempt;
- RBAC;
- execução de integrações.

---

# 4. Integrations

> **Status: RATIFICADO**

## Responsabilidade

`Integrations` transforma um `PackageVersion` em uma configuração executável dentro de:

```text
Organization
+
Environment
```

Ele governa a configuração concreta e o lifecycle configurável daquela integração.

## Distinção fundamental

```text
PackageVersion
→ definição reutilizável

Integration
→ configuração concreta

Run
→ execução concreta
```

## Integration

Uma Integration pertence a um único:

```text
Organization + Environment
```

```text
Organization
└── Environment
    └── Integration
```

O mesmo Package pode ser instanciado várias vezes.

## PackageVersion

Cada Integration referencia explicitamente um `PackageVersion`.

```text
Integration
→ PackageVersion
```

Publicar uma nova versão não altera Integrations existentes.

Upgrade é explícito.

## Owns

- `Integration`;
- Destination configuration;
- Trigger;
- Schedule;
- configuration overrides;
- `EnvironmentDeployment`;
- `HomologationRequest`;
- `Promotion`;
- Rollback record;
- `IdentityMapping`;
- Labels da Integration.

## Destination configuration

Configura como a Integration utiliza seus destinos.

Pode referenciar Connections, mas não possui os Secrets concretos.

```text
Integration
├── source configuration
└── destinations
    ├── destination A
    ├── destination B
    └── destination C
```

## Configuration overrides

Packages fornecem capacidades, defaults e requisitos.

Integrations fornecem configuração concreta.

```text
Package
→ capabilities
→ defaults
→ required configuration

Integration
→ overrides
→ Connections
→ scheduling
→ destinations
```

## Trigger e Schedule

Definem quando uma Integration deve originar um Run.

```text
Integration
└── Trigger / Schedule
    └── Run
```

A execução do Run não pertence a `Integrations`.

## EnvironmentDeployment

Representa qual configuração/versionamento está ativo em determinado Environment.

## Homologation

`HomologationRequest` governa validação e aprovação antes de promoção.

Pode referenciar Runs como evidência, mas não executa esses Runs.

## Promotion

Promoção leva uma configuração aprovada a outro Environment.

Não copia Secrets.

O target Environment usa suas próprias Connections.

## Rollback

Seleciona explicitamente uma configuração/versionamento anterior.

Runs anteriores continuam associados aos snapshots usados originalmente.

## IdentityMapping

Representa associação de identidades entre sistemas.

Exemplo:

```text
ERP Customer 42
→ Salesforce 9001
→ Billing 710
```

Scope conceitual:

```text
Organization
Environment
Integration
Destination
```

Distinção:

```text
Transformation
→ transforma payload

IdentityMapping
→ associa identidades externas
```

## Labels

Labels são metadata leve de classificação e busca.

Não possuem efeito direto sobre runtime.

Não criar um tagging framework universal.

## Public surface

```text
Integrations
├── Integrations.Destinations
├── Integrations.Triggers
├── Integrations.Deployments
├── Integrations.Homologations
└── Integrations.IdentityMappings
```

Facade:

```elixir
Integrations.create(...)
Integrations.get(...)
Integrations.activate(...)
Integrations.disable(...)
Integrations.get_execution_definition(...)
```

Destinations:

```elixir
Integrations.Destinations.configure(...)
```

Triggers:

```elixir
Integrations.Triggers.schedule(...)
```

Deployments:

```elixir
Integrations.Deployments.promote(...)
Integrations.Deployments.rollback(...)
```

Homologations:

```elixir
Integrations.Homologations.approve(...)
Integrations.Homologations.reject(...)
```

Identity mappings:

```elixir
Integrations.IdentityMappings.resolve(...)
```

As assinaturas ainda não estão congeladas.

## Execution definition

`Integrations` fornece uma definição resolvível para criação de Run.

```elixir
Integrations.get_execution_definition(...)
```

`Integrations` não cria o RunSnapshot e não executa o Run.

## Dependências

```text
Integrations
   ├──→ Organizations
   ├──→ Catalog
   └──→ Connections
```

## OTP e supervisão

Não possui necessidade atual de processos OTP próprios.

Pode começar principalmente com:

```text
Ecto
Repo
validation
configuration rules
deployment state
promotion rules
identity mappings
```

Scheduling durável pode usar Oban quando apropriado.

## Não pertence aqui

- Run;
- RunSnapshot;
- Record;
- Delivery;
- Attempt;
- Checkpoint;
- processos OTP do Run;
- Connector implementation;
- Operation implementation;
- Transport implementation;
- Secret concreto;
- execução do data plane.

---

# 5. Executions

> **Status: RATIFICADO**

## Responsabilidade

`Executions` transforma uma configuração de Integration em uma execução concreta, durável e recuperável.

Ele governa tanto o histórico durável da execução quanto o lifecycle operacional necessário para processá-la.

## Owns

### Execução

- `Run`;
- `RunSnapshot`.

### Data plane durável

- `Record`;
- `Delivery`;
- `Attempt`;
- `Enrichment`;
- `Checkpoint`.

### Lifecycle

- `ExecutionEvent`.

### Ownership e recovery

- runtime node ownership;
- `owner_node`;
- `generation`;
- fencing state;
- claim/recovery state;
- node heartbeat relacionado ao ownership de Runs.

### Runtime OTP

- Run supervision tree;
- `RunCoordinator`;
- Source Broadway pipeline;
- optional Enrichment Broadway pipeline;
- Destination Broadway pipelines;
- Registry usado pelo runtime;
- DynamicSupervisor de Runs.

## Run

`Run` representa uma execução concreta de uma Integration.

```text
Integration
→ Run
```

## RunSnapshot

No início do Run, `Executions` resolve a configuração necessária e persiste um snapshot imutável.

```text
Integration configuration
+
PackageVersion
+
Contract versions
+
effective configuration
+
Connection references
+
credential/version references
        ↓
RunSnapshot
```

O snapshot não contém Secrets em texto claro.

Mudanças posteriores na Integration não alteram Runs existentes.

## Record, Delivery e Attempt

```text
Run
└── Record
    └── Delivery
        └── Attempt
```

`Record` representa um item extraído da origem.

`Delivery` representa uma obrigação durável para um destino.

`Attempt` representa uma tentativa concreta daquela Delivery.

Destinos evoluem independentemente.

## Enrichment

`Enrichment` representa resultado durável de lookup externo realizado durante o processamento.

## Checkpoint

`Checkpoint` representa uma posição segura e durável de progresso.

Conceitualmente:

```text
fetch source page
        ↓
validate
        ↓
persist Records + Deliveries
        ↓
advance Checkpoint
```

## ExecutionEvent

Registra fatos significativos do lifecycle.

Exemplos:

```text
run_started
source_completed
checkpoint_advanced
destination_throttled
run_paused
run_resumed
run_completed
run_failed
```

Não é um log genérico do Broadway.

## Ownership de Run

Um Run pertence a um único BEAM node por vez.

PostgreSQL é a autoridade durável.

```text
owner_node
generation
```

`generation` funciona como fencing token.

Heartbeat é por BEAM node, não por Run.

## Recovery

Recovery utiliza:

```text
RunSnapshot
Checkpoint
durable Record/Delivery state
owner_node
generation
```

para reconstruir a execução.

## At-least-once

A semântica base é:

```text
at-least-once
```

O Leafcutter não promete `exactly-once` universal.

## Public surface

```text
Executions
├── Executions.Runs
├── Executions.Records
├── Executions.Deliveries
├── Executions.Attempts
└── Executions.Recovery
```

Runs:

```elixir
Executions.Runs.start(...)
Executions.Runs.pause(...)
Executions.Runs.resume(...)
Executions.Runs.cancel(...)
Executions.Runs.get(...)
```

Records:

```elixir
Executions.Records.list(...)
```

Deliveries:

```elixir
Executions.Deliveries.retry(...)
```

Attempts:

```elixir
Executions.Attempts.list(...)
```

Recovery:

```elixir
Executions.Recovery.claim(...)
```

As assinaturas ainda não estão congeladas.

## Dependências

```text
Executions
├──→ Organizations
├──→ Catalog
├──→ Connections
└──→ Integrations
```

Todas as interações entre contexts ocorrem por APIs públicas.

## OTP e supervisão

`Executions` é o primeiro Context ratificado que exige processos OTP próprios desde o início.

Conceitualmente:

```text
Executions runtime supervision
│
├── Registry
├── Run DynamicSupervisor
├── node heartbeat
│
└── Run supervision tree
    ├── RunCoordinator
    ├── Source Broadway
    ├── optional Enrichment Broadway
    └── Destination Broadway
        ├── destination A
        ├── destination B
        └── destination C
```

A árvore exata será ratificada durante o desenho da OTP application/runtime.

## RunCoordinator

Pertence ao control plane.

Não deve transportar Records nem virar bottleneck do data plane.

## Broadway

Pertence ao data plane.

Fornece:

```text
bounded concurrency
demand
batching
backpressure
processing pipelines
```

## Não pertence aqui

- configuração mutável da Integration;
- ownership de Package;
- definição de Contract;
- ownership de Connection;
- ownership de Secret;
- Connector implementation;
- Transport implementation;
- NotificationRule;
- AuditEvent.

---

# 6. Notifications

> **Status: RATIFICADO**

## Responsabilidade

`Notifications` transforma eventos relevantes da plataforma em entregas de notificação duráveis para recipients configurados.

Ele responde por perguntas como:

```text
Qual evento deve gerar uma notificação?

Quem deve receber?

Por qual canal?

A entrega foi concluída?

A entrega falhou?

Ela precisa ser tentada novamente?
```

`Notifications` reage a fatos produzidos por outros contexts.

Ele não controla o estado de `Integration`, `Run` ou outros domínios que originaram esses fatos.

## Owns

- `NotificationRule`;
- `NotificationChannel`;
- `Recipient`;
- `NotificationDelivery`.

## NotificationRule

Define quando um fato relevante deve gerar uma notificação.

Conceitualmente:

```text
event
+
filters
+
recipients
+
channel
→ notification
```

As regras podem futuramente utilizar Labels ou scope quando necessário, sem transformar Labels em um sistema de eventos.

## NotificationChannel

Representa como uma notificação é entregue.

Exemplos futuros:

```text
email
Slack
webhook
```

Não criar inicialmente um Context ou capability pública separada para cada canal.

## Recipient

`Recipient` representa quem ou onde recebe a notificação.

Ele pertence a uma Organization, mas é independente de `User`.

```text
User
→ ator que acessa o Leafcutter

Recipient
→ destino de comunicação
```

Exemplos:

```text
ana@acme.com
ops@acme.com
Slack #integrations
webhook operacional
```

Mesmo que um Recipient corresponda à mesma pessoa representada por um User, o sistema não precisa manter essa associação enquanto não houver requisito concreto.

Não criar relacionamento `Recipient -> User` por antecipação.

## NotificationDelivery

Representa a obrigação e o estado durável de uma entrega concreta de notificação.

Conceitualmente:

```text
NotificationRule
        ↓
Recipient
        ↓
NotificationDelivery
```

Pode registrar:

```text
pending
processing
completed
failed
retry state
```

A representação física será definida durante o desenho de persistência.

## Public surface

```text
Notifications
├── Notifications.Rules
└── Notifications.Recipients
```

Rules:

```elixir
Notifications.Rules.create(...)
Notifications.Rules.disable(...)
```

Recipients:

```elixir
Notifications.Recipients.create(...)
Notifications.Recipients.disable(...)
```

Entrega:

```elixir
Notifications.deliver_for_event(...)
```

As assinaturas ainda não estão congeladas.

Não criar inicialmente:

```text
Notifications.Email
Notifications.Slack
Notifications.Webhooks
```

sem necessidade concreta.

## Dependências

```text
Notifications
├──→ Organizations
├──→ Integrations
└──→ Executions
```

### Organizations

Fornece o scope organizacional necessário às regras e recipients.

### Integrations

Fornece fatos e referências relacionados a Integration quando necessários às regras de notificação.

### Executions

Fornece fatos relacionados a Runs, Deliveries, Attempts e lifecycle operacional.

`Notifications` não depende diretamente de:

```text
Catalog
Connections
Audit
```

## Durabilidade

PubSub sozinho não é suficiente para uma obrigação de notificação.

A estratégia inicial prevista é:

```text
NotificationDelivery
+
PostgreSQL
+
Oban
```

Oban é apropriado para o trabalho futuro/durável de entrega.

## OTP e supervisão

`Notifications` não possui necessidade atual de processos OTP próprios.

Não criar inicialmente:

```text
Notifications.Supervisor
Notifications.Dispatcher
Notifications.EmailServer
```

O lifecycle dos jobs duráveis pode ser gerenciado por Oban dentro da árvore supervisionada da OTP application que hospedar o context.

## Não pertence aqui

- `User`;
- `Role`;
- `Permission`;
- estado da Integration;
- estado do Run;
- `AuditEvent`;
- regras de negócio que originam os fatos.

---

# 7. Audit

> **Status: RATIFICADO**

## Responsabilidade

`Audit` registra, de forma durável e consultável, ações humanas e administrativas relevantes ocorridas na plataforma.

Ele responde por perguntas como:

```text
Quem realizou a ação?

O que aconteceu?

Sobre qual recurso?

Em qual Organization?

Em qual Environment?

Quando aconteceu?

Quais mudanças relevantes podem ser registradas sem expor dados sensíveis?
```

`Audit` registra fatos.

Ele não controla a regra de negócio que originou esses fatos.

## Owns

- `AuditEvent`;
- actor metadata;
- action;
- target reference;
- Organization/Environment scope;
- redacted change metadata.

## AuditEvent

`AuditEvent` representa um fato auditável persistido.

Conceitualmente:

```text
actor
+
action
+
target
+
scope
+
metadata
+
timestamp
→ AuditEvent
```

## Actor metadata

Registra quem realizou a ação.

Pode representar, conforme o caso:

```text
User
ServiceAccount
system actor
```

O AuditEvent deve armazenar informação suficiente para preservar o histórico sem depender de joins frágeis para reconstruir completamente o passado.

A estratégia física será definida posteriormente.

## Action

Representa a ação auditada.

Exemplos:

```text
integration.promoted
integration.disabled
run.cancelled
delivery.retried
secret.rotated
role.assigned
```

A nomenclatura definitiva será padronizada posteriormente.

## Target reference

Representa o recurso sobre o qual a ação ocorreu.

Conceitualmente:

```text
target_type
target_id
```

`Audit` não precisa conhecer o schema interno do target.

## Scope

AuditEvents podem ser scoped por:

```text
Organization
+
optional Environment
```

Isso permite consulta e autorização do histórico sem transformar Audit em proprietário desses scopes.

## Redacted change metadata

Metadata de mudanças pode ser persistida quando útil.

Nunca armazenar em texto claro:

```text
password
Secret value
OAuth refresh token
API key
credential payload
```

Dados sensíveis devem ser removidos ou redacted antes da persistência.

## Public surface

A API pública inicial é apenas:

```text
Audit
```

Com:

```elixir
Audit.record(...)
Audit.list(...)
```

Não criar inicialmente:

```text
Audit.Events
Audit.Writer
Audit.Queries
```

sem necessidade concreta.

## Dependências

`Audit` depende apenas de:

```text
Audit
   ↓
Organizations
```

`Organizations` fornece o scope organizacional necessário.

`Audit` não precisa conhecer como dependência de domínio:

```text
Catalog
Connections
Integrations
Executions
Notifications
```

Esses contexts podem originar fatos auditáveis, mas Audit recebe referências e metadata em vez de depender de seus schemas internos.

O mecanismo concreto pelo qual fatos obrigatórios chegam ao Audit será definido posteriormente, preservando durabilidade e evitando dependências circulares.

## Sink

Audit é um sink de fatos administrativos.

Outros contexts nunca devem consultar Audit para decidir suas próprias regras de negócio.

Evitar:

```text
"posso promover?"
→ consultar Audit
```

Preferir:

```text
domínio decide
→ ação acontece
→ fato auditável é registrado
```

## OTP e supervisão

`Audit` não possui necessidade atual de processos OTP próprios.

A implementação inicial pode usar:

```text
AuditEvent
+
Ecto
+
Repo
+
PostgreSQL
```

Não criar:

```text
Audit.Supervisor
Audit.Writer
Audit.Buffer
```

sem uma necessidade real.

Se volume ou requisitos futuros exigirem buffering ou processamento assíncrono, essa decisão será revisitada.

## Não pertence aqui

- regras de negócio;
- estado de Integration;
- estado de Run;
- NotificationRule;
- Secret values;
- autenticação;
- autorização.

---

# Dependências conceituais ratificadas

```text
Organizations
```

```text
Catalog
   ↓
Organizations
```

```text
Connections
   ├──→ Catalog
   └──→ Organizations
```

```text
Integrations
   ├──→ Connections
   ├──→ Catalog
   └──→ Organizations
```

```text
Executions
   ├──→ Integrations
   ├──→ Connections
   ├──→ Catalog
   └──→ Organizations
```

```text
Notifications
   ├──→ Executions
   ├──→ Integrations
   └──→ Organizations
```

```text
Audit
   └──→ Organizations
```

## Regras ratificadas

- `Organizations` não depende de outros contexts.
- `Catalog` depende apenas de `Organizations`.
- `Connections` depende apenas de `Catalog` e `Organizations`.
- `Integrations` depende apenas de `Connections`, `Catalog` e `Organizations`.
- `Executions` depende de `Integrations`, `Connections`, `Catalog` e `Organizations`.
- `Notifications` depende de `Executions`, `Integrations` e `Organizations`.
- `Audit` depende apenas de `Organizations`.
- dependências entre contexts ocorrem através de APIs públicas ou mecanismos explicitamente ratificados;
- outros contexts não acessam schemas e queries internos;
- nenhum context utiliza Audit como fonte de regra de negócio;
- nenhuma dependência circular conhecida foi introduzida nesta primeira rodada.

---

# Próxima fase

Todos os contexts passaram pela primeira ratificação individual:

```text
Organizations
Catalog
Connections
Integrations
Executions
Notifications
Audit
```

Antes de criar qualquer OTP application:

1. revisar o mapa completo em conjunto;
2. procurar responsabilidades duplicadas;
3. procurar dependências desnecessárias;
4. procurar dependências circulares indiretas;
5. revisar APIs públicas;
6. revisar quais contexts realmente precisam conviver na mesma OTP application;
7. somente então ratificar as boundaries da umbrella.
