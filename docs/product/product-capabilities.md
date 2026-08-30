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
- manifest digest obrigatório, imutável e globalmente único em novas PackageVersions;
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

### Operation executável

- behaviours síncronos de Read e Write;
- invocation/result values com credentials redigidas;
- cursor JSON opaco e conclusão por `nil`;
- write batch completo, ordenado e correlacionado por ref;
- partial success e erro normalizado;
- invariantes puras da Operation, independentes de Transport, Repo ou processo próprio.

### Transport HTTP bounded

- facade e Adapter contract síncronos;
- Request/Response/Error validados e com Inspect redigido;
- exatamente uma tentativa, sem redirect ou retry automático;
- Finch HTTP/1 com pool nomeado supervisionado e compartilhado por origem;
- connect/pool/receive/request timeouts finitos;
- response body limitado pelo menor cap central/por request;
- testes determinísticos sem internet nem credenciais reais.

### Package Manifest e binding compilada

- Manifest v1 com parsing bounded e JSON Schema Draft 2020-12;
- SHA-256 dos bytes exatos do manifest;
- refs source/destination ligadas a módulos Read/Write literais;
- cobertura, ordem, unicidade e behaviours validados em compile time;
- callbacks puros sem acesso ao filesystem em runtime;
- build inventory literal, dependencies Mix explícitas e closure da release.

### Package resolution compilada

- inventory literal ligada às Mix dependencies e à closure da release;
- resolução pública por digest exato e projeção imutável do Catalog;
- composição in-memory de módulos compilados com IDs autoritativos;
- rejeição de PackageVersion sem digest em Deployment e de binding indisponível/divergente em Run;
- nenhuma alteração em RunSnapshot v1.

## Capacidades ratificadas em desenvolvimento futuro

### Core de integração

- primeira Operation HTTP real (26C3 aberta);
- Integration Packages de produto;
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
