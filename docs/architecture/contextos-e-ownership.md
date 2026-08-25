# Contextos e ownership

> **Status: RATIFICAÇÃO EM ANDAMENTO.** `Organizations` está ratificado. Os demais contexts permanecem como propostas e devem ser aprovados individualmente antes de influenciarem a implementação.

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

As OTP applications do Leafcutter devem possuir árvore de supervisão desde sua criação. Um context, porém, só recebe um supervisor próprio quando possuir processos com lifecycle que justifiquem uma subtree dedicada.

---

## 1. Organizations

> **Status: RATIFICADO**

### Responsabilidade

`Organizations` é responsável por tenancy, escopo operacional e autorização dentro do Leafcutter.

O context responde por questões como:

```text
A qual Organization este recurso pertence?

Em qual Environment ele opera?

Quem pode agir dentro dessa Organization ou Environment?

O que esse ator está autorizado a fazer?
```

`Organizations` é um context de fundação e não depende de outros contexts de domínio do Leafcutter.

Outros contexts podem depender de sua API pública para resolver organização, ambiente, atores e autorização.

### Owns

- `Organization`;
- `Environment`;
- `User`;
- `ServiceAccount`;
- `Membership`;
- `Role`;
- `Permission`;
- access grants e assignments associados ao escopo organizacional.

Esse ownership é conceitual. A decisão sobre quais desses conceitos serão persistidos em tabelas próprias será tomada durante o desenho do modelo de dados.

### Organization

`Organization` é a principal fronteira de propriedade do produto.

Recursos pertencentes a clientes devem possuir um escopo organizacional explícito sempre que aplicável.

### Environment

`Environment` pertence a `Organizations`.

Ele representa uma subdivisão operacional de uma Organization.

Exemplos comuns:

```text
Organization
├── development
├── homologation
└── production
```

Os nomes não precisam ser hardcoded.

Outros domínios podem possuir recursos scoped por Environment, como:

```text
Connection
Integration
Run
IdentityMapping
Schedule
access grants
```

Esses recursos continuam pertencendo aos seus respectivos contexts. `Organizations` é proprietário apenas da identidade e lifecycle do Environment.

### Atores

`User` e `ServiceAccount` pertencem a `Organizations` enquanto atores do domínio e sujeitos de autorização.

`Membership` representa a relação entre um ator e uma Organization.

A boundary não assume ownership dos mecanismos concretos de autenticação.

Ficam fora deste context, por enquanto:

```text
password management
login sessions
OAuth/OIDC login
MFA
authentication refresh tokens
login attempts
```

A localização definitiva da autenticação será decidida quando essa capacidade for desenhada.

Não criar um context separado de Authentication ou Accounts apenas por antecipação.

### RBAC

RBAC pertence a `Organizations`.

A primitive fundamental é `Permission`.

`Role` agrupa permissions.

Grants e assignments associam atores às capacidades permitidas dentro de um scope.

O modelo conceitual é:

```text
who
→ User | ServiceAccount

what
→ Permission

where
→ Organization + optional Environment
```

Exemplos de permissions:

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

A lista definitiva de permissions e sua estratégia física de persistência ainda não estão congeladas.

### Public surface

A API pública inicial é dividida em:

```text
Organizations
├── Organizations.Environments
└── Organizations.Access
```

A facade raiz controla operações sobre `Organization`.

Exemplo conceitual:

```elixir
Organizations.create(...)
Organizations.get(...)
Organizations.disable(...)
```

`Organizations.Environments` controla o lifecycle dos Environments.

Exemplo conceitual:

```elixir
Organizations.Environments.create(...)
Organizations.Environments.get(...)
Organizations.Environments.disable(...)
```

`Organizations.Access` concentra Membership, Role, Permission e autorização.

Exemplo conceitual:

```elixir
Organizations.Access.add_member(...)
Organizations.Access.remove_member(...)
Organizations.Access.assign_role(...)
Organizations.Access.revoke_role(...)
Organizations.Access.authorize(...)
```

Essas assinaturas são conceituais e não representam contratos de implementação congelados.

Não criar inicialmente módulos públicos separados como:

```text
Organizations.Users
Organizations.Roles
Organizations.Permissions
```

Eles só devem surgir se uma capability pública real justificar essa separação.

### Autorização

Controllers e plugs podem realizar autorização na borda.

Operações privilegiadas de domínio também devem receber actor e scope explícitos quando necessário.

Conceitualmente:

```text
authorize(
  actor,
  permission,
  scope
)
```

onde:

```text
actor
→ User | ServiceAccount

permission
→ capability solicitada

scope
→ Organization + optional Environment
```

A assinatura concreta e os tipos de retorno serão definidos durante a implementação da API pública.

### Dependências

`Organizations` não depende de nenhum outro context de domínio.

Ele não deve conhecer:

```text
Integration
Connection
Secret
Package
Run
Delivery
Connector
```

Isso permite que `Organizations` funcione como uma boundary de fundação utilizada pelos demais domínios.

### OTP e supervisão

`Organizations` não exige, neste momento, processos OTP próprios apenas por existir como context.

Isso não significa ausência de supervisão.

A OTP application que hospedar `Organizations` deve possuir sua árvore de supervisão desde o início.

Conceitualmente:

```text
Application
└── root Supervisor
    ├── Repo
    ├── infrastructure children
    └── context processes, quando existirem
```

Se `Organizations` futuramente possuir processos com lifecycle próprio, esses processos devem entrar nessa árvore e podem receber uma subtree dedicada.

Não criar um `Organizations.Supervisor` vazio apenas para representar a existência do context.

### Não pertence aqui

- mecanismos concretos de autenticação;
- configuração de Integration;
- Integration Package ou Package Version;
- Connection;
- Secret;
- Run;
- Record;
- Delivery;
- Attempt;
- homologação funcional de Integration;
- Notification;
- armazenamento de AuditEvent.

---

## 2. Catalog

> **Status: PROPOSTA PARA RATIFICAÇÃO**

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

A facade raiz não deve acumular toda a API. Capabilities devem dividir Run control, queries, Deliveries, Attempts e Recovery quando essas boundaries forem ratificadas.

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

A entrega utiliza trabalho durável. Oban é a primitive inicial prevista para esse tipo de obrigação.

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

## Dependências conceituais propostas

Apenas `Organizations` está ratificado neste momento.

O restante do grafo continua sujeito à ratificação dos demais contexts.

Direção já aprovada:

```text
Organizations
      ↑
      │
other domain contexts
```

`Organizations` não depende de outros contexts de domínio.

O desenho completo só será congelado depois da ratificação individual de Catalog, Connections, Integrations, Executions, Notifications e Audit.

O grafo final deve eliminar qualquer dependência circular antes da criação das OTP applications.
