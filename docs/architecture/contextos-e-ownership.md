# Contextos e ownership

> **Status: RATIFICAÇÃO EM ANDAMENTO.** `Organizations`, `Catalog`, `Connections` e `Integrations` estão ratificados. Os demais contexts permanecem como propostas e devem ser aprovados individualmente antes de influenciarem a implementação.

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

Schemas e queries pertencem ao context que controla o dado. Outros contexts usam somente sua API pública.

A existência de um conceito dentro de um context define ownership de domínio. Não implica automaticamente a existência de uma tabela, processo OTP ou módulo dedicado.

As OTP applications do Leafcutter devem possuir árvore de supervisão desde sua criação. Um context só recebe um supervisor próprio quando possuir processos com lifecycle que justifiquem uma subtree dedicada.

---

## 1. Organizations

> **Status: RATIFICADO**

### Responsabilidade

`Organizations` é responsável por tenancy, escopo operacional e autorização dentro do Leafcutter.

### Owns

- `Organization`;
- `Environment`;
- `User`;
- `ServiceAccount`;
- `Membership`;
- `Role`;
- `Permission`;
- access grants e assignments.

O ownership é conceitual. A estratégia física de persistência será definida posteriormente.

### Environment

`Environment` pertence a `Organizations` e representa uma subdivisão operacional de uma Organization.

```text
Organization
├── development
├── homologation
└── production
```

Outros contexts podem possuir recursos scoped por Environment sem que esses recursos passem a pertencer a `Organizations`.

### Atores e autenticação

`User` e `ServiceAccount` pertencem ao context como atores e sujeitos de autorização.

`Membership` representa a relação entre ator e Organization.

Mecanismos concretos de autenticação ficam fora desta boundary, incluindo:

```text
password management
login sessions
OAuth/OIDC login
MFA
authentication refresh tokens
login attempts
```

Não criar um context separado de Authentication ou Accounts por antecipação.

### RBAC

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

Grants e assignments associam atores às capacidades permitidas dentro de determinado scope.

### Public surface

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

Facade principal:

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

As assinaturas são conceituais e ainda não representam contratos congelados.

### Dependências

`Organizations` não depende de outros contexts de domínio.

Outros contexts podem depender de sua API pública.

### OTP e supervisão

`Organizations` não exige processos OTP próprios neste momento.

A OTP application que hospedar o context possuirá sua árvore de supervisão desde a criação.

Não criar um `Organizations.Supervisor` vazio apenas para representar o context.

### Não pertence aqui

- mecanismos concretos de autenticação;
- Integration;
- Package;
- Connection;
- Secret;
- Run;
- Record;
- Delivery;
- Attempt;
- homologação funcional;
- Notification;
- armazenamento de AuditEvent.

---

## 2. Catalog

> **Status: RATIFICADO**

### Responsabilidade

`Catalog` é responsável por registrar, versionar e disponibilizar os building blocks reutilizáveis da plataforma.

O Catalog controla identidade, metadata, versões, publicação, disponibilidade e descoberta.

Ele não executa os artefatos que registra.

### Owns

#### Connectors

- Connector metadata;
- Operation metadata;
- Connector versions;
- publication metadata;
- availability metadata.

O Catalog não possui a implementação executável dos Connectors ou Operations.

```text
Catalog
→ identidade
→ metadata
→ versões
→ disponibilidade

connector implementation
→ código executável fora do Catalog
```

#### Contracts

- `Contract`;
- `ContractVersion`.

O Catalog registra e versiona os contratos.

Runtime e outros consumidores utilizam versões resolvidas desses contratos.

#### Integration Packages

- `Package`;
- `PackageVersion`;
- `PackageDependency`;
- publication metadata;
- availability metadata.

O código executável dos Integration Packages permanece fora do Catalog, inicialmente em:

```text
packages/
```

O Catalog registra a identidade e as versões desses artefatos.

#### Categories

- `CatalogCategory`.

`CatalogCategory` serve exclusivamente para classificação, descoberta e busca.

Categorias não possuem efeito sobre execução ou comportamento de runtime.

### Escopo

O Catalog suporta:

```text
platform-wide
→ artefatos oficiais

organization-scoped
→ artefatos privados de uma Organization
```

Não criar dois Catalog contexts distintos para esses casos.

### Public surface

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

### Dependências

`Catalog` depende apenas de `Organizations`.

```text
Catalog
   ↓
Organizations
```

A interação ocorre somente através da API pública de `Organizations`.

### OTP e supervisão

`Catalog` não possui necessidade atual de processos OTP próprios.

A OTP application que hospedar Catalog será supervisionada desde sua criação.

Não criar um `Catalog.Supervisor` vazio.

### Não pertence aqui

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
- execução de Integration Package;
- execução de Connector;
- orchestration de runtime.

---

## 3. Connections

> **Status: RATIFICADO**

### Responsabilidade

`Connections` é responsável por representar e resolver o acesso configurado de uma `Organization` e `Environment` a sistemas externos.

O context responde por questões como:

```text
Como este Environment acessa este sistema externo?

Qual configuração de acesso deve ser utilizada?

Quais credenciais estão associadas à Connection?

Qual versão válida do Secret deve ser resolvida para o runtime?
```

`Connections` não executa a integração.

Ele disponibiliza configuração e credenciais para os contexts que precisam acessar sistemas externos.

### Owns

- `Connection`;
- `Secret`;
- `SecretVersion`;
- authentication configuration;
- OAuth token state;
- OAuth refresh state;
- secret rotation metadata;
- organization/environment scope da Connection.

### Connection

`Connection` representa a configuração não sensível necessária para acessar uma instância ou conta de um sistema externo.

Pode conter, conforme o Connector:

```text
base URL
account identifier
region
timeouts
connector reference
authentication scheme configuration
secret reference
```

Dados sensíveis não devem ser armazenados diretamente em `Connection`.

### Secret

`Secret` representa credenciais sensíveis associadas a uma Connection.

`SecretVersion` representa versões das credenciais ao longo de rotation e atualização.

Secrets não devem aparecer em texto claro em:

```text
Integration Package
Run Snapshot público
logs
ExecutionEvent
AuditEvent
API responses
```

### OAuth

Configuração e estado durável necessários para OAuth pertencem a `Connections`.

Isso inclui, quando aplicável:

```text
access token
refresh token
expiration state
refresh metadata
rotation state
```

O mecanismo concreto de refresh poderá futuramente envolver processos OTP ou jobs duráveis caso exista necessidade real de lifecycle ou coordenação.

Essa necessidade não é assumida antecipadamente.

### Escopo

Connections são scoped por:

```text
Organization
└── Environment
    └── Connection
```

Connections de environments diferentes são independentes.

Uma Connection de homologação não pode ser utilizada como fallback automático em produção.

Promoções entre environments não copiam Secrets.

### Relação com Connector

Uma Connection referencia um Connector conhecido pelo `Catalog`.

```text
Connection
→ Connector identity/version metadata
→ authentication requirements
```

`Connections` não conhece a implementação concreta do Connector.

A implementação executável continua fora deste context.

### Public surface

A API pública inicial é:

```text
Connections
└── Connections.Secrets
```

Facade principal:

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

As assinaturas são conceituais e ainda não representam contratos congelados.

Não criar inicialmente:

```text
Connections.OAuth
Connections.Auth
Connections.SecretServer
```

Essas capabilities só devem surgir quando complexidade real justificar a separação.

### Dependências

`Connections` depende apenas de:

```text
Connections
   ├──→ Organizations
   └──→ Catalog
```

`Organizations` é utilizado para validar e resolver o scope de Organization e Environment.

`Catalog` é utilizado para resolver identidade, metadata e requisitos do Connector.

Toda interação ocorre por APIs públicas.

### OTP e supervisão

`Connections` não possui necessidade atual de processos OTP próprios.

Suas responsabilidades iniciais podem ser implementadas principalmente com:

```text
Ecto
Repo
secret resolution
OAuth state persistence
rotation logic
```

A OTP application que hospedar `Connections` será supervisionada desde sua criação.

Não criar processos dedicados sem lifecycle, estado temporal, coordenação ou isolamento de falha que os justifique.

### Não pertence aqui

- Connector implementation;
- Operation implementation;
- Transport implementation;
- Integration configuration;
- Package;
- Run;
- Record;
- Delivery;
- Attempt;
- RBAC;
- execução de integrações.

---

## 4. Integrations

> **Status: RATIFICADO**

### Responsabilidade

`Integrations` é responsável por transformar um `PackageVersion` em uma configuração executável dentro de uma `Organization + Environment`.

O context governa a configuração concreta de uma integração, seu lifecycle configurável e sua promoção entre environments.

Uma `Integration` não representa código reutilizável e não representa uma execução.

A distinção é:

```text
Package / PackageVersion
→ definição reutilizável do que pode ser executado

Integration
→ configuração concreta desse PackageVersion

Run
→ execução concreta dessa Integration
```

### Integration

`Integration` pertence a um único `Organization + Environment`.

```text
Organization
└── Environment
    └── Integration
```

O mesmo Package pode ser instanciado várias vezes em Organizations ou Environments diferentes.

Cada Integration concreta permanece isolada dentro de seu scope operacional.

### PackageVersion

Uma `Integration` referencia explicitamente um `PackageVersion`.

```text
Integration
→ PackageVersion
```

A publicação de um novo PackageVersion não altera automaticamente Integrations existentes.

Upgrade de PackageVersion é explícito.

Isso garante previsibilidade e permite que Runs continuem referenciando definições imutáveis.

### Owns

`Integrations` possui conceitualmente:

- `Integration`;
- Destination configuration;
- Trigger configuration;
- Schedule configuration;
- Integration configuration overrides;
- `EnvironmentDeployment`;
- `HomologationRequest`;
- `Promotion`;
- Rollback record;
- `IdentityMapping`;
- Labels aplicadas à Integration.

### Destination configuration

A configuração dos destinos pertence a `Integrations`.

Ela define como aquela Integration concreta utiliza seus destinos.

Pode referenciar Connections pertencentes ao context `Connections`, mas não possui os Secrets concretos.

Conceitualmente:

```text
Integration
├── source configuration
└── destinations
    ├── destination A
    ├── destination B
    └── destination C
```

Os detalhes físicos da representação ainda não estão congelados.

### Configuration overrides

Overrides específicos da Integration pertencem a este context.

Eles representam valores concretos aplicados sobre defaults e requisitos definidos pelo Package.

O modelo conceitual é:

```text
Package
→ capabilities
→ defaults
→ required configuration

Integration
→ concrete overrides
→ Connections
→ scheduling
→ destination configuration
```

### Trigger e Schedule

`Trigger` e `Schedule` pertencem a `Integrations`.

Eles definem quando uma Integration deve originar um Run.

```text
Integration
└── Trigger / Schedule
    └── cria Run
```

A criação e execução concreta do Run não pertence a `Integrations`.

Essa responsabilidade pertence a `Executions`.

O mecanismo durável de scheduling poderá utilizar Oban sem transformar o próprio Trigger em um processo OTP permanente.

### EnvironmentDeployment

`EnvironmentDeployment` pertence a `Integrations`.

Ele representa qual estado/versionamento da Integration está ativo em determinado Environment.

Package Versions permanecem imutáveis.

Deployments selecionam explicitamente a versão utilizada.

### Homologation

`HomologationRequest` pertence a `Integrations`.

Homologação governa o processo de validação de uma configuração/versionamento antes de sua promoção.

Pode referenciar evidências e Runs executados por `Executions`, mas o workflow de aprovação pertence a `Integrations`.

### Promotion

`Promotion` pertence a `Integrations`.

Promoção move uma configuração aprovada para um Environment alvo.

Ela não copia Secrets.

O Environment alvo utiliza suas próprias Connections e Secrets.

Conceitualmente:

```text
PackageVersion 1.4.0
      ↓
Integration em homologation
      ↓
validation / approval
      ↓
promotion
      ↓
production deployment
      ↓
production Connections
```

### Rollback

Rollback pertence a `Integrations`.

Rollback seleciona explicitamente um estado ou PackageVersion anterior permitido.

Runs anteriores permanecem associados aos snapshots utilizados no momento de sua execução.

### IdentityMapping

`IdentityMapping` pertence a `Integrations`.

Ele representa a associação entre identidades de entidades externas ao longo da integração.

Exemplo:

```text
ERP Customer 42
→ Salesforce Customer 9001
→ Billing Customer 710
```

IdentityMapping é scoped pelo menos por:

```text
Organization
Environment
Integration
Destination
```

A estrutura física definitiva será definida durante o desenho do modelo de dados.

Transformation e IdentityMapping são responsabilidades diferentes:

```text
Transformation
→ transforma payload

IdentityMapping
→ associa identidades externas
```

### Labels

Labels aplicadas à Integration pertencem a `Integrations`.

Elas são metadata leve para classificação e busca.

Labels não devem virar um sistema universal de tagging da plataforma sem necessidade concreta.

Não possuem efeito direto sobre execução.

### Public surface

A API pública inicial é:

```text
Integrations
├── Integrations.Destinations
├── Integrations.Triggers
├── Integrations.Deployments
├── Integrations.Homologations
└── Integrations.IdentityMappings
```

Facade principal:

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

As assinaturas são conceituais e ainda não representam contratos congelados.

Capability modules só devem permanecer quando representarem capacidades públicas reais.

### Execution definition

`Integrations` deve ser capaz de produzir uma definição resolvível para criação de Run.

Conceitualmente:

```elixir
Integrations.get_execution_definition(...)
```

Essa definição pode reunir referências necessárias para que `Executions` construa um snapshot imutável.

`Integrations` não cria o snapshot de Run e não executa o processamento.

### Dependências

`Integrations` depende de:

```text
Integrations
   ├──→ Organizations
   ├──→ Catalog
   └──→ Connections
```

#### Organizations

Usado para:

```text
Organization scope
Environment scope
authorization
```

#### Catalog

Usado para:

```text
Package
PackageVersion
Contracts
artifact metadata
```

#### Connections

Usado para:

```text
source Connection references
destination Connection references
connection availability/configuration
```

Todas as interações ocorrem por APIs públicas.

### Não depende de

`Integrations` não depende de:

```text
Executions
Notifications
Audit
```

`Executions` consome definições de `Integrations`, nunca o contrário.

Notifications e Audit podem receber fatos relacionados à Integration por mecanismos apropriados, mas não fazem parte da regra de negócio deste context.

### OTP e supervisão

`Integrations` não possui necessidade atual de processos OTP próprios.

Suas responsabilidades iniciais podem ser implementadas principalmente através de:

```text
Ecto
Repo
validation
configuration rules
deployment state
promotion rules
identity mappings
```

Scheduling durável pode utilizar Oban quando apropriado.

A OTP application que hospedar `Integrations` será supervisionada desde sua criação.

Não criar um `Integrations.Supervisor` vazio.

Processos dedicados só devem ser adicionados quando lifecycle, estado temporal, concorrência, coordenação ou isolamento de falha justificarem sua existência.

### Não pertence aqui

- Run;
- RunSnapshot;
- Record;
- Delivery;
- Attempt;
- Checkpoint;
- processos OTP de Run;
- Connector implementation;
- Operation implementation;
- Transport implementation;
- Secret concreto;
- execução de Package;
- execução do data plane.

---

## 5. Executions

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade: criar snapshots imutáveis, executar Runs e manter o histórico operacional durável.

### Owns

- Run;
- RunSnapshot;
- Record;
- Delivery;
- Attempt;
- Enrichment;
- Checkpoint;
- ExecutionEvent;
- runtime node ownership fields;
- generation/fencing token;
- recovery state.

### Public surface proposta

```elixir
Executions.Runs.start(...)
Executions.Runs.pause(...)
Executions.Runs.resume(...)
Executions.Runs.cancel(...)
Executions.Runs.get(...)

Executions.Records.list(...)
Executions.Deliveries.retry(...)
Executions.Attempts.list(...)
Executions.Recovery.claim(...)
```

### Regra de snapshot

Ao iniciar um Run, Executions consulta APIs públicas de Integrations, Catalog e Connections, persiste um snapshot e, a partir daí, o processamento usa o snapshot em vez de reler configuração mutável.

### Risco de god context

Executions é grande, mas potencialmente coeso.

A facade raiz não deve acumular toda a API.

---

## 6. Notifications

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade: regras e entrega durável de notificações.

### Owns

- NotificationRule;
- NotificationChannel;
- Recipient;
- NotificationDelivery.

### Public surface proposta

```elixir
Notifications.Rules.create(...)
Notifications.Rules.disable(...)
Notifications.Recipients.create(...)
Notifications.deliver_for_event(...)
```

A entrega utiliza trabalho durável.

PubSub sozinho não é suficiente para uma obrigação de notificação.

---

## 7. Audit

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade: registrar ações humanas e administrativas relevantes.

### Owns

- AuditEvent;
- actor metadata;
- action;
- target reference;
- environment/organization scope;
- redacted change metadata.

### Public surface proposta

```elixir
Audit.record(...)
Audit.list(...)
```

Audit é um sink.

Outros contexts podem registrar fatos, mas não devem depender do conteúdo de Audit para executar regras de negócio.

---

## Dependências conceituais ratificadas

Em direção de dependência:

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

Regras ratificadas:

- `Organizations` não depende de outros contexts.
- `Catalog` depende apenas de `Organizations`.
- `Connections` depende apenas de `Catalog` e `Organizations`.
- `Integrations` depende apenas de `Connections`, `Catalog` e `Organizations`.
- dependências entre contexts ocorrem somente através de APIs públicas.
- nenhum dos contexts ratificados depende de `Executions`.
- nenhuma dependência circular foi introduzida até este ponto.

O restante do grafo permanece em proposta até a ratificação individual de:

```text
Executions
Notifications
Audit
```

O grafo final deve ser revisado novamente antes da criação das OTP applications.
