# Decisões em aberto

> **Status: ABERTO.** Itens já ratificados ou materializados foram removidos desta lista.

RunSnapshot v1 está materializado. As authorities upstream mínimas e o workflow EnvironmentDeployment → definition v1 foram ratificados no ADR-0018. Catalog e Connections mínimos estão materializados, incluindo SecretVersion bindings exatos. Integration e EnvironmentDeployment formam a próxima fronteira.

## Domínio

- provenance futura de Organization/Environment/Integration/Deployment;
- modelo futuro de invocation/idempotency além da semântica atual de criar Runs distintas;
- histórico de deployment;
- homologation evidence e promotion records;
- Record/Delivery/Attempt/Checkpoint;
- ExecutionEvent e AuditEvent;
- durable cross-context fact mechanism.

## Runtime

- lifecycle completo de Run;
- pause/resume/cancel/terminalização;
- política de rolling upgrade e remoção de formatos de RunSnapshot suportados;
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
- enforcement futuro de config não sensível por schemas tipados;
- lifecycle, revogação e retenção de SecretVersion;
- payload redaction;
- external error exposure;
- expanded permission matrix.

## Infraestrutura

- cluster discovery;
- provider e deployment topology;
- Postgres HA, backup e migration sequencing;
- metrics/logging/tracing stack;
- RuntimeNode cleanup;
- retenção de Run e RunSnapshot;
- object storage e storage tiers.

## Futuro deliberadamente não decidido

- external queue;
- Redis;
- package isolation;
- analytics DB;
- specialized nodes;
- multi-source joins;
- SDKs;
- API Management completo.

