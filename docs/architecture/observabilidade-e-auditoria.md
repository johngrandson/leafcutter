# Observabilidade e auditoria

> **Status: TELEMETRY DE HEARTBEAT MATERIALIZADA; OBSERVABILIDADE COMPLETA E AUDIT FUTUROS.**

## Materializado

`NodeHeartbeat` emite:

```text
[:leafcutter, :runtime, :node, :heartbeat]
```

Metadata inclui runtime node identity. O evento é efêmero; a authority de liveness está no PostgreSQL.

A application Phoenix também possui Telemetry foundation gerada.

## Observabilidade futura da plataforma

Métricas planejadas:

- DB latency e pool pressure;
- heartbeat age e recovery claims;
- number of locally supervised Runs;
- Run recovery failures/backoff;
- Broadway demand e throughput;
- Delivery backlog por destination;
- HTTP latency, rate limits e retries;
- memory e scheduler utilization.

## Execution monitoring futuro

Consultará dados de domínio:

```text
Run
├── Records
├── Deliveries
├── Attempts
├── Enrichments
└── ExecutionEvents
```

## Audit futuro

`AuditEvent` será append-only e registrará ações humanas/administrativas, como:

- permission e role changes;
- secret rotation;
- homologation approval;
- promotion/rollback;
- manual retry/cancel.

Raw secrets não entram em Audit.

## Notifications futuras

NotificationRules consumirão fatos duráveis self-contained. PubSub sozinho não garante entrega. Oban poderá executar deliveries duráveis de menor cardinalidade.

## Ainda aberto

- metrics backend;
- log aggregation e redaction;
- tracing strategy;
- ExecutionEvent schema;
- AuditEvent schema;
- durable fact/outbox mechanism;
- retention e export.
