# Durabilidade, checkpoint e recovery

> **Status: OWNERSHIP/RECOVERY MATERIALIZADOS; DURABLE FAN-OUT RATIFICADO PARA O FUTURO.**

## Semântica base

```text
at-least-once
```

Se o sistema não consegue provar que um efeito externo terminou, o trabalho pode ser executado novamente. Exactly-once universal não é prometido.

## Durabilidade já existente

### RuntimeNode

```text
id
node_name
last_heartbeat_at
```

`id` representa uma incarnação. O nome Erlang não é identidade. Heartbeat usa o relógio do PostgreSQL.

### Run ownership

```text
owner_node_id
generation
ownership_acquired_at
```

`generation` é fencing token. Release e futuras escritas críticas precisam aplicar o token na mesma instrução SQL da mutação.

### Recovery local e de node

```text
process crash
→ Supervisor restarts local process

local tree missing but ownership still current
→ RunRecovery reconstructs same generation

node heartbeat expired
→ another node reclaims
→ generation increments
```

`RunRecovery` usa polling, lotes e `FOR UPDATE SKIP LOCKED`.

## Durabilidade futura do data plane

Para um Record com dois destinos:

```text
Record 42
├── Delivery CRM pending
└── Delivery Billing pending
```

Transação ratificada:

```text
insert Records
+ insert all Deliveries
+ advance Checkpoint
= one commit
```

Se a transação falha, o checkpoint não avança.

## Checkpoint futuro

O source pode manter cursor operacional em memória. PostgreSQL guarda o último cursor seguro. Reprocessamento após crash é esperado.

Checkpoint é estado durável; não haverá `CheckpointSupervisor` sem lifecycle real.

## Delivery e Attempt futuros

Estados mínimos esperados de Delivery:

```text
pending
processing
completed
failed
```

`Attempt` registra a chamada concreta. Sucesso parcial de batch é preservado por item.

## Error model ratificado

```text
validation      → no automatic retry
authentication  → blocked until configuration changes
rate_limited    → retry later
timeout         → retry
temporary       → retry
permanent       → no automatic retry
```

A forma final dos structs e códigos públicos ainda será fechada junto aos contracts de Connector/Operation.

## Sem fila externa inicial

```text
SourceBroadway
→ PostgreSQL durable backlog
→ DestinationBroadway
```

Fila externa entra somente se métricas demonstrarem que o backlog durável no PostgreSQL é o gargalo dominante.

## Recovery não significa criação de trabalho

O scanner atual recupera apenas Runs `running`. Runs `pending` precisam de definição executável imutável antes de se tornarem elegíveis automaticamente.
