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
- conteúdo publicado protegido contra append, update e delete.

## Próximo estágio: authorities upstream e resolução

O contract deste estágio foi ratificado no ADR-0018. A materialização ocorrerá em sub-slices ordenados.

- Contract/ContractVersion e Package/PackageVersion/endpoints;
- Connections e SecretVersion bindings mínimos;
- Integration + EnvironmentDeployment persistidos;
- resolver semântico de EnvironmentDeployment para definition v1;
- criação de Run a partir da definition resolvida.

## Reliable integration core

- Contracts + JSON Schema/JSV;
- Connector/Operation/Transport contracts;
- Generic HTTP Connector;
- PackageVersion 1 Source → N Destinations;
- manual and automatic Run startup from snapshot.

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
