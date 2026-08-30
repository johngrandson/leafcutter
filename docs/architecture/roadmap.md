# Roadmap arquitetural

> O roadmap preserva a plataforma-alvo sem fingir que todas as capacidades já existem. A sequência pode mudar; boundaries ratificadas não dependem de datas.

## Foundation materializada

### Plataforma

- umbrella com quatro OTP applications;
- grafo de dependências sem ciclos;
- Repo, PubSub e Oban compartilhados;
- migrations centralizadas;
- harness, ADRs e quality gates.

### Organizations

- Organization e Environment lifecycle;
- User, ServiceAccount e Membership;
- Role, Permission e assignments scoped;
- authorization para User e ServiceAccount.

### Runtime control plane

- RuntimeNode liveness durável;
- Run lifecycle mínimo;
- ownership + generation fencing;
- claim/release;
- Registry local e DynamicSupervisor;
- RunSupervisor + RunCoordinator;
- RunRecovery por polling com `SKIP LOCKED`.
- RunSnapshot 1:1 e imutável;
- workflow público de criação de Run;
- eligibility segura de Run `pending`;
- references/config congeladas sem raw secrets.

### Catalog parcial

- Connector como identidade global;
- ConnectorVersion com versão opaca;
- Operations source/destination;
- publicação atômica e sealing no PostgreSQL;
- conteúdo publicado protegido contra append, update e delete;
- Contract e ContractVersion com publicação executável por schema object/boolean, publicados e imutáveis;
- compilação/validação reutilizáveis e rejeição de legado em novas PackageVersions;
- Package e PackageVersion com topologia relacional 1 Source → 1..N Destinations;
- endpoints ordenados pinando Operation e ContractVersion;
- cardinalidade, compatibilidade e imutabilidade protegidas no PostgreSQL.

### Connections mínimo

- Connection ligada a Organization, Environment e Connector estável;
- config não sensível validada como JSON object;
- Secret e SecretVersion identities sem material secreto;
- binding opcional e exato para SecretVersion do mesmo scope;
- update de config/binding e disable idempotente;
- locks de scope e constraints de integridade no PostgreSQL;
- SecretVersion imutável e única dentro de Secret.

### Integrations mínimo

- Integration organization-scoped ligada a Package estável;
- identidade protegida contra mudança de Organization, Package e name;
- create/get/disable com validação de Organization ativa e disable idempotente;
- um EnvironmentDeployment completo por Integration/Environment;
- PackageVersion, promotable/local config e bindings completos por endpoint;
- create/get/replace atômicos com cobertura exata e compatibilidade de Connector;
- locks ordenados de Organization, Environment, Integration, deployment e Connections.

### Resolução executável

- descoberta preliminar somente dos parent IDs imutáveis;
- resolução transacional por APIs públicas dos contexts;
- revalidação de lifecycle, scope, PackageVersion, bindings, Connectors e SecretVersions;
- deep merge de promotable/local config;
- congelamento de definition v1 e criação atômica de Run + RunSnapshot;
- chamadas repetidas criando Runs distintas.

## Próximo estágio: reliable integration core

O contract upstream foi materializado integralmente conforme o ADR-0018. A fronteira executável foi dividida para não acoplar schema, behaviours e HTTP em uma única mudança.

### Slice 26A — ContractVersion executável

**Materializado integralmente em Catalog, PackageVersion, EnvironmentDeployment e resolução de Run.**

- schema JSONB object/boolean imutável em novas ContractVersions;
- versões identity-only legadas preservadas e não executáveis;
- JSON Schema Draft 2020-12 fixo;
- JSV build obrigatório na publicação;
- refs somente locais e nenhuma resolução externa;
- `Contracts.compile/1` e `validate/2`;
- validator reutilizado pelo futuro processo de Run, sem cache global inicial;
- PackageVersion rejeitando versões legadas, materializado;
- EnvironmentDeployment create/replace e resolver rejeitando versões legadas, materializados;
- RunSnapshot v1 inalterado.

### Slice 26B — Operation executável

**Contract concreto materializado conforme o ADR-0021.**

- behaviours síncronos separados de Read e Write;
- invocation/result structs com config resolvida e credentials efêmeras;
- cursor JSON opaco, com `nil` como conclusão;
- result por item completo, ordenado e correlacionado por ref;
- pontos source/destination explícitos de validação dos Contracts;
- error struct alinhado à retry taxonomy.

### Slice 26C1 — Transport HTTP

**Contract concreto materializado conforme o ADR-0022.**

- facade HTTP e Adapter behaviour síncrono;
- Request/Response/Error com validation e Inspect redigido;
- exatamente uma tentativa, sem redirect ou retry;
- Finch HTTP/1 com pool nomeado supervisionado;
- timeouts finitos e response body cap;
- testes determinísticos com servidor local.

### Slice 26C2 — Package binding e module resolution

**Contract concreto materializado conforme o ADR-0023.**

- Manifest v1 bounded + digest byte-exact e bindings Read/Write compiladas, materializados;
- `manifest_sha256` imutável/globalmente único em PackageVersion, com legado legível, materializado;
- `packages/build.exs` literal + Mix path dependencies/release closure, materializados;
- resolução via digest + projeção do Catalog, sem module string/UUID registry/atom dinâmico, materializada;
- enforcement de digest em Deployment e resolução compilada antes de Run/RunSnapshot, materializada.

### Slice 26C3 — primeira referência HTTP

**Aberto; depende da escolha de um sistema externo real.**

- primeira Connector/Operation publicada;
- autenticação e codec vendor-specific;
- status, rate-limit e vendor-error mapping;
- conformance tests sem credentials reais.

PackageVersion 1 Source → N Destinations, criação automática de Run, a boundary in-memory de
Operation, o Transport HTTP bounded e o contract 26C2 estão materializados. A primeira
referência permanece em 26C3 e exige ratificação própria.

## Data plane durável

- Record, Delivery, Attempt e Checkpoint;
- SourceBroadway;
- DestinationBroadway por destination;
- durable fan-out atomicity;
- Transformation 1→0/1/N;
- retry e partial batch results;
- IdentityMapping.

## Operação e governança

- lifecycle completo de Run;
- pause/resume/cancel;
- schedules via Oban;
- Enrichment;
- NotificationRules;
- AuditEvents;
- homologation, promotion e rollback;
- secret rotation e payload access controls.

## Ecossistema

- official/custom connectors;
- package tooling e manifest v1;
- build/publish/registry;
- OpenAPI import;
- Postman derivado.

## Futuro condicionado por demanda

- inbound APIs;
- Database/SFTP transports;
- object storage;
- package isolation;
- specialized nodes;
- analytics store;
- external queue somente com gargalo comprovado;
- multi-source orchestration;
- SDKs após estabilização.
