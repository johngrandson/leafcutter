# Capacidades do produto Leafcutter

## Foundations disponíveis

### Tenancy e access control

- Organizations e Environments;
- Users, Memberships e ServiceAccounts;
- Roles e permissions;
- assignments organization/environment-scoped;
- authorization para User e ServiceAccount.

### Runtime control plane

- identity/liveness de runtime nodes;
- Run lifecycle mínimo;
- ownership e generation fencing;
- criação atômica de Run + RunSnapshot v1;
- criação transacional de Run a partir de EnvironmentDeployment;
- congelamento de PackageVersion, ContractVersions, destination order, effective config, Connections e SecretVersion IDs;
- revalidação de ContractVersions executáveis antes de persistir Run e RunSnapshot;
- per-Run supervision;
- automatic recovery de Runs `running` e `pending` elegíveis;
- concorrência distribuída baseada em PostgreSQL.

### Plataforma

- umbrella boundaries;
- Repo/PubSub/Oban compartilhados;
- Phoenix API foundation;
- quality gates e harness.

### Catalog parcial

- Connector e ConnectorVersion;
- Operations source/destination;
- publicação atômica de versão e Operations;
- sealing e imutabilidade no PostgreSQL;
- Contract e ContractVersion com publicação executável por schema JSONB object/boolean;
- publicação com validação e build JSV, compilação e validação reutilizáveis;
- Package, PackageVersion e endpoints relacionais;
- topologia 1 Source → 1..N Destinations publicada atomicamente;
- rejeição de ContractVersions identity-only legadas em novas PackageVersions;
- ordem, references, role compatibility e imutabilidade protegidas no banco.

### Connections mínimo

- Connection environment-scoped ligada a Connector estável;
- config não sensível como JSON object;
- binding opcional e exato de SecretVersion;
- Secret e SecretVersion scoped por Organization/Environment;
- update de config/binding e disable idempotente;
- locks contra disable concorrente e integridade relacional no PostgreSQL;
- nenhum raw secret, ciphertext, provider locator ou credential persistido.

### Integrations mínimo

- Integration organization-scoped ligada a Package estável;
- lifecycle create/get/disable e lock ativo para workflows compostos;
- um EnvironmentDeployment completo por Integration/Environment;
- PackageVersion, promotable/local config e bindings completos por endpoint;
- create/get/replace atômicos;
- validação de scope, lifecycle, executabilidade de ContractVersion, cobertura e Connector compatibility sob locks determinísticos;
- descoberta de scope imutável e locks de resolução por APIs públicas.

## Capacidades ratificadas em desenvolvimento futuro

### Core de integração

- Operation executável (contract do Slice 26B ratificado, ainda sem código);
- Transport + primeira referência HTTP (Slice 26C ainda a ratificar);
- Integration Packages;
- lifecycle ampliado de Connections, OAuth, rotation e secret providers;
- lifecycle ampliado de Integrations, Triggers, promotion e homologation.

### Data plane

- one Source → N Destinations;
- pagination;
- validation nas duas bordas;
- Transformation 1→0/1/N;
- optional Enrichment;
- batching/backpressure Broadway;
- partial batch success;
- retries/rate limits;
- durable Record/Delivery fan-out;
- Checkpoint e Attempts;
- IdentityMapping;
- execution monitoring.

### Governance

- User/ServiceAccount authentication;
- homologation;
- promotion/rollback;
- payload access permissions;
- secret rotation;
- AuditEvents e Notifications.

## Futuro condicionado por demanda

- Inbound API;
- API Management;
- multi-transport;
- package isolation;
- object storage/analytics;
- specialized nodes;
- external queue;
- multi-source joins;
- SDKs após API estabilizada.
