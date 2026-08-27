# Decisões em aberto

> **Status: ABERTO.** Itens já ratificados ou materializados foram removidos desta lista.

O contrato de RunSnapshot v1 não está mais aberto. Ele foi ratificado em `docs/decisions/ADR-0017-run-snapshot-v1.md` e detalhado em `docs/specifications/run-snapshot-v1.md`. A próxima atividade é sua materialização, não uma nova decisão arquitetural.

## Domínio

- schemas e APIs públicas de Catalog;
- Connection/Secret/SecretVersion;
- Integration/EnvironmentDeployment;
- resolução semântica de EnvironmentDeployment para RunSnapshot v1;
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
