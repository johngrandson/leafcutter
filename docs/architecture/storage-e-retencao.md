# Storage e retenção

> **Status: POSTGRESQL FOUNDATION MATERIALIZADA; POLÍTICAS E TIERS FUTUROS.**

## Estado atual

PostgreSQL armazena:

```text
Organizations/RBAC tables
runtime_nodes
runs
Oban tables
```

Um único Repo e uma única migration stream são usados.

## Papel do PostgreSQL

PostgreSQL continuará sendo a operational truth para metadata, ownership, checkpoint e backlog durável inicial.

## Payloads futuros

Na primeira versão do data plane, JSONB pode ser usado por simplicidade. O modelo deve separar metadata de content para permitir externalização posterior.

```text
PostgreSQL
→ operational metadata and current backlog

Object Storage future
→ large immutable payloads and archives

Analytics Store future
→ high-volume historical aggregation
```

## Retenção ainda aberta

- RuntimeNode incarnations antigas;
- Runs terminais;
- Records e Deliveries;
- Attempts e request/response metadata;
- raw payloads;
- AuditEvents e ExecutionEvents;
- notification history.

## Segurança

Payload access terá permission própria. Secrets nunca são armazenados como payload de execução. Redaction e encryption policy ainda precisam ser fechadas.

## Regra de evolução

Object storage ou analytics DB entram quando volume, custo ou query pattern justificarem. Não introduzir tiers antecipadamente.
