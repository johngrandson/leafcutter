# ADR-0004 — Estado operacional e estado durável

- Status: Accepted
- Estado de implementação: MATERIALIZADO NO CONTROL PLANE

## Decisão

OTP/Broadway mantém estado operacional de alta frequência. PostgreSQL mantém estado recuperável, histórico, ownership, checkpoints e intenções.

## Estado atual

```text
RuntimeNode heartbeat
Run owner_node_id
generation
ownership timestamps
```

são duráveis. Registry, supervisors, coordinator e recovery process são reconstruíveis.

## Futuro preservado

Record, Delivery, Attempt e Checkpoint aplicarão a mesma separação no data plane Broadway.

## Consequências

Supervisor reinicia processo; PostgreSQL explica de onde continuar. GenServer não é banco.
