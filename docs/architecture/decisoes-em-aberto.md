# Decisões em aberto

> **Status: ABERTO.** Itens já ratificados ou materializados foram removidos desta lista.

RunSnapshot v1 e as authorities upstream estão materializados conforme o ADR-0018. ContractVersion e Operation executáveis estão materializados conforme os ADRs 0019 e 0021. O ADR-0022 ratifica o Transport HTTP 26C1 e separa Package Manifest/module resolution (26C2) da primeira referência de produto (26C3).

## Domínio

- provenance futura de Organization/Environment/Integration/Deployment;
- modelo durável futuro de invocation/idempotency além da semântica atual de criar Runs distintas;
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

- Package Manifest JSON Schema v1 e executable module binding (26C2);
- package inclusion no build/release (26C2);
- mapping de `operation_id` para módulo compilado via binding versionada (26C2);
- primeiro Connector/Operation HTTP de produto e vendor mapping (26C3);
- request payload/batch limits além do response body cap de 26C1;
- cache compartilhado de validators somente se medição justificar;
- bundling/registry para referências externas futuras.

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
