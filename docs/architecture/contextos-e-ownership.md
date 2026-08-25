# Contextos e ownership

> **Status: RATIFICAÇÃO EM ANDAMENTO.** `Organizations`, `Catalog`, `Connections`, `Integrations` e `Executions` estão ratificados. `Notifications` e `Audit` permanecem como propostas.

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

Responde por questões como:

```text
Qual configuração exata este Run executou?

Quais Records foram extraídos?

Quais Deliveries foram criadas?

Quais Attempts ocorreram?

Onde o processamento parou?

Qual node possui o Run?

Como o Run é retomado após falha?
```

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
- node heartbeat necessário ao ownership de Runs.

### Runtime OTP

- Run supervision tree;
- `RunCoordinator`;
- Source Broadway pipeline;
- optional Enrichment Broadway pipeline;
- Destination Broadway pipelines;
- Registry usado pelo runtime;
- DynamicSupervisor de Runs.

Os nomes físicos dos módulos poderão ser refinados durante a implementação, mas essas responsabilidades pertencem a `Executions`.

## Run

`Run` representa uma execução concreta de uma Integration.

```text
Integration
→ Run
```

Um Run possui lifecycle próprio e estado operacional reconstruível.

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

O snapshot não deve conter Secrets em texto claro.

Depois da criação do snapshot, o Run não deve depender de reler continuamente configuração mutável da Integration.

Mudanças futuras na Integration não alteram Runs existentes.

## Record

`Record` representa um item extraído da origem durante um Run.

```text
Run
└── Record
```

O Record mantém a ocorrência interna da execução e sua relação com a identidade externa da origem.

## Delivery

`Delivery` representa a obrigação durável de enviar o resultado relacionado a um Record para um destino específico.

```text
Record
├── Delivery → Destination A
├── Delivery → Destination B
└── Delivery → Destination C
```

Cada destino evolui independentemente.

Uma Destination lenta ou indisponível não deve bloquear as demais.

Delivery é também uma representação durável de trabalho.

Ela não precisa ser duplicada automaticamente como Oban Job.

## Attempt

`Attempt` representa uma tentativa concreta de executar uma Delivery.

```text
Delivery
├── Attempt #1
├── Attempt #2
└── Attempt #3
```

Attempts preservam histórico de execução externa, incluindo sucesso, falha e informações normalizadas de erro.

## Relação principal

```text
Run
└── Record
    └── Delivery
        └── Attempt
```

## Enrichment

`Enrichment` representa resultado durável de lookup externo realizado durante o processamento.

```text
Record
└── Enrichment
```

Pode armazenar resultado, status e informações necessárias para retry/reuse conforme a política futura.

## Checkpoint

`Checkpoint` representa uma posição segura e durável de progresso da origem.

```text
Run
└── Checkpoint
```

Checkpoint só avança quando o trabalho anterior necessário já foi persistido duravelmente.

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

A persistência do fan-out e o avanço seguro do checkpoint devem respeitar atomicidade apropriada.

## ExecutionEvent

`ExecutionEvent` registra fatos significativos do lifecycle.

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

Não deve virar um log genérico de todos os detalhes internos do Broadway.

## Ownership de Run

Um Run pertence a um único BEAM node por vez.

PostgreSQL é a autoridade durável de ownership.

O modelo conceitual utiliza:

```text
owner_node
generation
```

`generation` funciona como fencing token.

Distributed Erlang pode ajudar na detecção rápida de falhas, mas não é autoridade de ownership.

## Node heartbeat

Existe heartbeat por BEAM node, não um heartbeat independente por Run.

Quando o heartbeat de um node expira, Runs pertencentes a ele podem ser reclamados por outro node através de operação durável e fenced.

## Recovery

Recovery utiliza:

```text
RunSnapshot
Checkpoint
durable Record/Delivery state
owner_node
generation
```

para reconstruir a subtree do Run em outro node.

OTP recupera falhas locais através de supervisão.

PostgreSQL + fencing permitem recuperação após perda de node.

## At-least-once

A semântica base é:

```text
at-least-once
```

Se o resultado externo for incerto, o trabalho pode ser tentado novamente.

Idempotência, Source Identity, IdentityMapping e operações de destino apropriadas reduzem efeitos de replay.

O Leafcutter não promete `exactly-once` universal.

## Public surface

A API pública inicial é:

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

`Executions` depende de:

```text
Executions
├──→ Organizations
├──→ Catalog
├──→ Connections
└──→ Integrations
```

### Organizations

Usado para scope e autorização.

### Integrations

Fornece a definição configurada que origina a execução.

### Catalog

Fornece PackageVersion, ContractVersion e metadata imutável necessária à resolução do snapshot.

### Connections

Fornece configuração e referências de credenciais necessárias ao runtime.

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

Não espalhar inicialmente uma única Run subtree entre múltiplos nodes.

## RunCoordinator

`RunCoordinator` pertence ao control plane da execução.

Deve tratar lifecycle de alto nível, como:

```text
start
pause
resume
cancel
source_done
destination_done
run_done
```

Não deve transportar Records ou se tornar bottleneck do data plane.

## Broadway

Broadway pertence ao data plane.

É responsável por primitives como:

```text
bounded concurrency
demand
batching
backpressure
processing pipelines
```

Não reimplementar manualmente essas capacidades sem necessidade concreta.

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

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade proposta: configurar regras e executar entrega durável de notificações.

## Owns proposto

- `NotificationRule`;
- `NotificationChannel`;
- `Recipient`;
- `NotificationDelivery`.

## Public surface proposta

```elixir
Notifications.Rules.create(...)
Notifications.Rules.disable(...)

Notifications.Recipients.create(...)

Notifications.deliver_for_event(...)
```

PubSub sozinho não é suficiente para obrigações de notificação.

A boundary ainda precisa ser ratificada.

---

# 7. Audit

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade proposta: registrar ações humanas e administrativas relevantes.

## Owns proposto

- `AuditEvent`;
- actor metadata;
- action;
- target reference;
- Organization/Environment scope;
- redacted change metadata.

## Public surface proposta

```elixir
Audit.record(...)
Audit.list(...)
```

Audit deve funcionar como sink.

Outros contexts podem registrar fatos, mas não devem consultar Audit para executar suas regras de negócio.

A boundary ainda precisa ser ratificada.

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

Regras ratificadas:

- `Organizations` não depende de outros contexts.
- `Catalog` depende apenas de `Organizations`.
- `Connections` depende apenas de `Catalog` e `Organizations`.
- `Integrations` depende apenas de `Connections`, `Catalog` e `Organizations`.
- `Executions` depende de `Integrations`, `Connections`, `Catalog` e `Organizations`.
- dependências entre contexts ocorrem somente através de APIs públicas;
- nenhuma dependência circular foi introduzida até este ponto.

Ainda precisam ser ratificados:

```text
Notifications
Audit
```

Depois disso, o Context Map completo deve passar por uma revisão conjunta antes da criação das OTP applications.
