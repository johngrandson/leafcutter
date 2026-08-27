# Decisões em aberto

> **Status: ABERTO.** Itens já ratificados ou materializados foram removidos desta lista.

## Próxima decisão

### RunSnapshot e criação pública de Run

Fechar:

- relação 1:1 entre Run e RunSnapshot;
- definition attrs e error contract;
- PackageVersion/ContractVersion references;
- effective config congelada;
- Connection e SecretVersion references sem raw secrets;
- atomicidade de criação;
- quando `pending` entra no recovery automático.

## Domínio

- schemas e APIs públicas de Catalog;
- Connection/Secret/SecretVersion;
- Integration/EnvironmentDeployment;
- histórico de deployment;
- homologation evidence e promotion records;
- Record/Delivery/Attempt/Checkpoint;
- ExecutionEvent e AuditEvent;
- durable cross-context fact mechanism.

## Runtime

- lifecycle completo de Run;
- pause/resume/cancel/terminalização;
- data-plane ownership checks;
- persistence batch sizes;
- Delivery claim visibility;
- retry policy final;
- backlog/storage limits;
- recovery wake-up hints além de polling.

## Contracts e packages

- Package Manifest JSON Schema v1;
- package inclusion no build/release;
- Connector/Operation/Transport behaviours;
- JSON Schema compilation/cache;
- HTTP client e pool strategy.

## Segurança

- User authentication;
- ServiceAccount credentials;
- secret provider/encryption;
- payload redaction;
- external error exposure;
- expanded permission matrix.

## Infraestrutura

- cluster discovery;
- provider e deployment topology;
- Postgres HA, backup e migration sequencing;
- metrics/logging/tracing stack;
- RuntimeNode cleanup;
- object storage e retention.

## Futuro deliberadamente não decidido

- external queue;
- Redis;
- package isolation;
- analytics DB;
- specialized nodes;
- multi-source joins;
- SDKs;
- API Management completo.
