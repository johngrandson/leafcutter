# Contextos e ownership

> **Status: RATIFICAÇÃO EM ANDAMENTO.** `Organizations` e `Catalog` estão ratificados. Os demais contexts permanecem como propostas e devem ser aprovados individualmente antes de influenciarem a implementação.

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

A separação é:

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

A existência de `ContractVersion` não define ainda a estratégia física de armazenamento ou cache dos schemas compilados.

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

A existência conceitual de `CatalogCategory` não implica obrigatoriamente uma tabela dedicada.

### Escopo

O Catalog suporta dois tipos de entrada:

```text
platform-wide
→ artefatos oficiais e reutilizáveis da plataforma

organization-scoped
→ artefatos privados pertencentes a uma Organization
```

Exemplos:

```text
Official Connector
→ platform-wide

Custom Connector privado
→ organization-scoped

Package privado
→ organization-scoped
```

Não criar dois Catalog contexts distintos para esses casos.

O scope faz parte da metadata da entrada.

### Public surface

A API pública inicial é:

```text
Catalog
├── Catalog.Packages
├── Catalog.Contracts
└── Catalog.Connectors
```

#### Packages

Responsável por registro, versionamento, publicação e consulta de Packages.

Exemplos conceituais:

```elixir
Catalog.Packages.register(...)
Catalog.Packages.publish_version(...)
Catalog.Packages.get_version(...)
```

#### Contracts

Responsável por registro, versionamento e acesso aos Contracts.

Exemplos conceituais:

```elixir
Catalog.Contracts.register(...)
Catalog.Contracts.compile(...)
Catalog.Contracts.validate(...)
```

A localização definitiva de compile/validate na API pública poderá ser refinada durante a implementação caso essas operações se mostrem responsabilidade de outro componente.

#### Connectors

Responsável por identidade, metadata, versões e descoberta de Connectors e Operations.

Exemplos conceituais:

```elixir
Catalog.Connectors.register(...)
Catalog.Connectors.get_operation(...)
```

As assinaturas não estão congeladas.

### Dependências

`Catalog` depende apenas de `Organizations`.

```text
Catalog
   ↓
Organizations
```

Essa dependência existe para suportar entradas privadas scoped por Organization.

A interação ocorre somente através da API pública de `Organizations`.

`Catalog` não acessa schemas ou queries internos de `Organizations`.

### Não depende de

`Catalog` não depende de:

```text
Connections
Integrations
Executions
Notifications
Audit
```

Esses contexts poderão consumir Catalog, mas Catalog não deve conhecer seus conceitos.

### OTP e supervisão

`Catalog` não possui necessidade atual de processos OTP próprios.

Suas responsabilidades iniciais são principalmente:

```text
Ecto
Repo
versionamento
queries
contract handling
metadata
```

A OTP application que hospedar Catalog será supervisionada desde sua criação.

Não criar um `Catalog.Supervisor` vazio.

Processos específicos só devem surgir se existir lifecycle, estado temporal, concorrência, coordenação ou isolamento de falha que os justifique.

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

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade: acesso configurado a sistemas externos.

### Owns

- Connection;
- Secret;
- SecretVersion;
- Connector authentication configuration;
- durable OAuth refresh state;
- secret rotation metadata.

### Public surface proposta

```elixir
Connections.create(...)
Connections.resolve(...)
Connections.disable(...)

Connections.Secrets.rotate(...)
Connections.Secrets.resolve_for_runtime(...)
```

### Regras

- Connection guarda configuração não sensível e referência ao Secret.
- Secret nunca aparece em Package, Run Snapshot público, logs ou AuditEvent em texto claro.
- Connections são environment-scoped.

---

## 4. Integrations

> **Status: PROPOSTA PARA RATIFICAÇÃO**

Responsabilidade: instanciar Packages para Organizations/Environments e governar seu lifecycle configurável.

### Owns

- Integration;
- Destination configuration;
- Trigger/Schedule configuration;
- Integration configuration overrides;
- EnvironmentDeployment;
- HomologationRequest;
- Promotion;
- Rollback record;
- IdentityMapping;
- Labels aplicadas à Integration.

### Public surface proposta

```elixir
Integrations.create(...)
Integrations.activate(...)
Integrations.disable(...)
Integrations.get_execution_definition(...)

Integrations.Destinations.configure(...)
Integrations.Triggers.schedule(...)
Integrations.Deployments.promote(...)
Integrations.Homologations.approve(...)
Integrations.IdentityMappings.resolve(...)
```

### Não pertence aqui

- processamento de Records;
- Attempts;
- processos OTP de Run;
- implementação de Connector;
- secrets concretos.

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

Até o momento:

```text
Organizations

     ↑

  Catalog
```

Ou, em direção de dependência:

```text
Catalog
   ↓
Organizations
```

Regras já ratificadas:

- `Organizations` não depende de outros contexts.
- `Catalog` depende apenas de `Organizations`.
- essa dependência ocorre via API pública.
- nenhuma dependência adicional do Catalog foi aprovada.

O restante do grafo permanece em proposta até a ratificação individual dos contexts restantes.

O grafo final deve eliminar qualquer dependência circular antes da criação das OTP applications.
