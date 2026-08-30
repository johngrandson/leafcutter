# Decisões em aberto

> **Status: ABERTO.** Itens já ratificados ou materializados foram removidos desta lista.

RunSnapshot v1 e as authorities upstream estão materializados conforme o ADR-0018.
ContractVersion, Operation executável, Transport HTTP 26C1 e Package
Manifest/build/module resolution 26C2 estão materializados conforme os ADRs 0019, 0021, 0022
e 0023. A primeira referência de produto permanece separada em 26C3.

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

- primeiro Connector/Operation HTTP de produto e vendor mapping (26C3);
- artifact hashing/signing, remote distribution e package retention/rolling upgrade;
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
