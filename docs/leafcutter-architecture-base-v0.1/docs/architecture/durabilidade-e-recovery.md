# Durabilidade, checkpoint e recovery

## Semântica

O Leafcutter assume `at-least-once`.

```text
Se não é possível provar que o efeito terminou,
o trabalho pode ser executado novamente.
```

Exactly-once não é prometido entre sistemas externos. Idempotency, upsert e IdentityMapping podem produzir efeito efetivamente único quando o destino suporta.

## Fan-out durável

Para um Record com dois destinos:

```text
Record 42
├── Delivery CRM pending
└── Delivery Billing pending
```

Records, todas as Deliveries e o checkpoint seguro são persistidos em uma transação.

## Checkpoint

O Source Producer mantém cursor operacional em memória. PostgreSQL guarda o último cursor seguro.

```text
Producer current cursor = 47
Postgres safe cursor    = 45
```

Crash pode reprocessar 46-47. Isso é esperado.

Não criar `CheckpointSupervisor`. Checkpoint é estado durável, não lifecycle próprio.

## Estados mínimos

Evitar write amplification. Delivery precisa de poucos estados duráveis significativos:

```text
pending
processing
completed
failed
```

Detalhes de alta frequência permanecem no runtime.

## Error model

```text
:validation      → no automatic retry
:authentication  → no retry until configuration changes
:rate_limited    → retry later
:timeout         → retry
:temporary       → retry
:permanent       → no automatic retry
```

Write Operations preservam sucesso parcial por item.

## Recovery local

Se um processo ou pipeline cai, o Supervisor reinicia. Estado durável permite reconstrução.

## Recovery de node

Um Run pertence a um node por vez.

```text
runtime_nodes
→ one heartbeat per BEAM node

runs
→ owner_node
→ generation
```

Distributed Erlang `nodedown` é sinal rápido, não autoridade.

Quando heartbeat expira, outro node pode claimar atomicamente o Run, incrementar `generation`, carregar snapshot/checkpoint e reiniciar sua árvore.

`generation` funciona como fencing token. Escritas críticas de owner antigo devem ser rejeitadas.

## Registry

Elixir Registry é local ao node e serve para localizar processos locais por Run ID. Não é mecanismo de exclusividade de cluster.

## Sem fila externa inicial

```text
Source Broadway
→ bulk insert Records + Deliveries + Checkpoint
→ Postgres durable backlog
→ Destination Broadways
```

Fila externa só entra após métricas demonstrarem que o Postgres no caminho de ingestão é o gargalo dominante.
