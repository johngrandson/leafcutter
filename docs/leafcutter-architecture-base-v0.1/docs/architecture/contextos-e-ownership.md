# Contextos e ownership

> **Status: PROPOSTA PARA RATIFICAÇÃO.** Este mapa organiza as decisões já aceitas, mas cada context ainda deve ser aprovado individualmente.

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

## 1. Organizations

Responsabilidade: fronteira de propriedade, acesso e escopo organizacional.

### Owns

- Organization;
- Environment;
- User;
- ServiceAccount;
- Membership;
- Role;
- Permission;
- environment-scoped access grants.

### Public surface proposta

```elixir
Organizations.create(...)
Organizations.get(...)
Organizations.disable(...)

Organizations.Environments.create(...)
Organizations.Environments.get(...)

Organizations.Access.add_member(...)
Organizations.Access.authorize(...)
```

### Não pertence aqui

- configuração de Integration;
- Package Version;
- Connection Secret;
- Run;
- homologação funcional de uma Integration.

## 2. Catalog

Responsabilidade: catálogo versionado de building blocks reutilizáveis.

### Owns

- Connector metadata;
- Operation metadata;
- Official/Custom Connector versions;
- Contract;
- ContractVersion;
- Package;
- PackageVersion;
- PackageDependency;
- CatalogCategory.

### Public surface proposta

```elixir
Catalog.Packages.register(...)
Catalog.Packages.publish_version(...)
Catalog.Packages.get_version(...)

Catalog.Contracts.register(...)
Catalog.Contracts.compile(...)
Catalog.Contracts.validate(...)

Catalog.Connectors.register(...)
Catalog.Connectors.get_operation(...)
```

### Observação

A implementação concreta de Connector continua em `leafcutter_connectors`; o Catalog controla identidade, metadata, versões e disponibilidade.

## 3. Connections

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

## 4. Integrations

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

## 5. Executions

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

Executions é grande, mas coeso. A facade raiz não deve acumular tudo. Capabilities devem dividir Run control, queries, Deliveries, Attempts e Recovery.

## 6. Notifications

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

A entrega utiliza Oban. PubSub não é suficiente para uma obrigação de notificação.

## 7. Audit

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

Audit é um sink: outros contexts podem registrar fatos, mas não devem depender do conteúdo de Audit para executar regra de negócio.

## Dependências conceituais propostas

```text
Organizations
    ▲
    │
Connections      Catalog
    ▲              ▲
    └──── Integrations
              ▲
              │
          Executions

Notifications reads configured rules/scopes and schedules durable deliveries.
Audit receives administrative facts from all contexts.
```

O desenho final deve eliminar qualquer dependência circular antes da criação das apps.
