# Decisões em aberto

Estas decisões não devem ser tratadas como fechadas apenas porque aparecem como proposta em documentos.

## Imediatas

1. Ratificar Context Map, context por context.
2. Ratificar apps da umbrella e dependências.
3. Definir ownership de Repo, migrations, PubSub e Oban entre apps.
4. Definir estratégia de compilação de `packages/` na mesma release.
5. Fechar Package Manifest JSON Schema v1.
6. Definir Ecto schemas, campos, constraints e índices.
7. Fechar API surface e error envelope OpenAPI.

## Runtime

- algoritmo concreto de pause/resume/cancel;
- limites de backlog e storage backpressure;
- granularidade de persistence batch;
- claim timeout/visibility de Deliveries;
- política de retry/backoff;
- processo de graceful shutdown;
- validação de `generation` em todas as escritas críticas.

## Segurança e governança

- permission matrix inicial;
- secret encryption/provider;
- policy de payload redaction;
- homologation evidence model;
- production promotion approvals.

## Infraestrutura

- provider;
- cluster discovery;
- Postgres topology/backups;
- object storage;
- metrics/logging stack;
- deployment/migration sequencing.

## Futuro deliberado

- external queue;
- Redis;
- package isolation;
- dedicated analytics DB;
- multi-source joins;
- SDKs;
- standalone CLI;
- API Management completo.
