# Observabilidade, monitoring e auditoria

## Execution Monitoring

É uma visão sobre dados do domínio:

```text
Run
├── Records
├── Deliveries
├── Attempts
├── Enrichments
└── ExecutionEvents
```

Responde perguntas como:

- quantos Records foram persistidos;
- quais destinations estão atrasados;
- quais Deliveries falharam;
- por que um Attempt falhou;
- qual checkpoint foi atingido;
- qual Package/Contract/config foi usado.

## Platform Observability

É separada de Execution Monitoring:

- throughput;
- Broadway demand/backlog;
- mailbox sizes quando relevante;
- memory;
- DB latency;
- node health;
- HTTP latency;
- rate-limit pressure;
- Telemetry events.

## Attempt

Attempt registra uma tentativa técnica concreta:

- start/end/duration;
- transport metadata;
- normalized error;
- status code quando aplicável;
- references para request/response payload;
- generation/owner metadata quando necessário.

## ExecutionEvent

Apenas mudanças relevantes:

```text
run_started
checkpoint_advanced
source_completed
destination_throttled
run_paused
run_resumed
run_completed
run_failed
```

Não persistir cada evento interno do Broadway.

## AuditEvent

Registra ações humanas/administrativas:

- promotion;
- approval;
- rollback;
- secret rotation;
- manual retry;
- cancel;
- permission change.

Dados sensíveis devem ser redigidos.

## PubSub

PubSub transmite atualizações efêmeras para consumidores operacionais e futuro frontend. Não é fonte da verdade e não garante entrega posterior.

## Notifications

Notification Rules reagem a eventos duráveis e enviam via Oban para Channels/Recipients. Labels podem filtrar regras, mas não representam estado.
