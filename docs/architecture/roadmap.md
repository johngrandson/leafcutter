# Roadmap arquitetural por releases

> O roadmap descreve o produto completo em etapas. Datas e numeração fina podem mudar; boundaries não devem depender do cronograma.

## V0 - Foundation

- umbrella vazia;
- documentação, ADRs e harness;
- CI mínimo;
- context map ratificado;
- apps e dependency graph;
- Repo/Postgres base;
- OpenAPI foundation;
- package specification draft.

## V1 - Reliable HTTP integration core

- Organizations e Environments básicos;
- Catalog mínimo;
- JSON Schema + JSV;
- Generic HTTP Connector;
- Package Versions compiladas com a release;
- Connections/Secrets básicos;
- one Source -> N Destinations;
- Transformations 1->0/1/N;
- durable Records/Deliveries;
- Broadway source/destination pipelines;
- manual Run;
- checkpoint e `at-least-once`;
- Attempts, Execution Monitoring API;
- IdentityMapping;
- OpenAPI + Postman derivado.

## V1.x - Reliability and operations

- retries avançados e rate limits;
- schedules via Oban;
- shared Enrichment pipelines;
- notification rules;
- node heartbeat, ownership e recovery;
- multi-node homogeneous deployment;
- graceful shutdown/deploy recovery;
- audit events.

## V2 - Governance

- RBAC granular;
- service accounts;
- homologation;
- promotion/rollback;
- environment-scoped permissions;
- payload access controls;
- secret rotation/versioning;
- deployment history.

## V3 - Package and Connector ecosystem

- Official Connectors iniciais;
- Custom Connector lifecycle;
- Mix-based package validation/build/publish;
- Package dependency resolution;
- artifact/registry design;
- immutable Contract registry;
- OpenAPI import.

## V4 - Inbound and multi-transport

- Inbound Endpoints;
- inbound OpenAPI revisions;
- Database/SFTP/other Transports conforme demanda;
- Codecs CSV/XML conforme demanda;
- object storage for payloads;
- audit exports.

## V5 - Scale and isolation

- specialized node roles somente se medido;
- package artifact isolation;
- external queue somente se Postgres durable backlog for gargalo comprovado;
- analytics store;
- advanced capacity/fairness controls;
- multi-region probes/runtime se houver caso comercial.

## V6+ - Advanced integration platform

- API Management completo;
- API Consumers/Client Credentials;
- multi-source orchestration;
- joins/windowed aggregation;
- developer portal;
- SDKs após API estabilizada;
- standalone CLI somente se Mix tooling se tornar insuficiente.
