# Runtime OTP e Broadway

> **Status: CONTROL PLANE MATERIALIZADO; DATA PLANE RATIFICADO — NÃO MATERIALIZADO.**

## Separação fundamental

```text
OTP control plane
→ lifecycle, ownership, coordenação e recovery

Broadway data plane
→ demand, concorrência, batching e backpressure de Records/Deliveries
```

## Supervision tree atual

```text
LeafcutterRuntime.Application
├── RunRegistry
├── RunDynamicSupervisor
├── NodeHeartbeat
└── RunRecovery
```

`RunRegistry` é local, com keys únicas. Não representa exclusividade de cluster.

`NodeHeartbeat` persiste uma identidade por incarnação em `runtime_nodes` usando o relógio do PostgreSQL.

`RunRecovery` usa polling autoritativo. O processo global é desabilitado em testes e substituído por instâncias isoladas quando necessário.

## Ownership durável

`Run` contém:

```text
status
owner_node_id
generation
ownership_acquired_at
```

Claim explícito:

```text
transaction
→ SELECT Run FOR UPDATE
→ validate claimant RuntimeNode
→ evaluate current owner
→ assign or reject
```

Semântica:

```text
unowned
→ claim + generation increment

stale owner
→ reclaim + generation increment

same active owner
→ idempotent token

other active owner
→ reject
```

Release aplica `run_id + owner_node_id + generation` no mesmo UPDATE.

## Árvore por Run atual

```text
RunDynamicSupervisor
└── RunSupervisor <run_id>
    └── RunCoordinator
```

O `RunSupervisor` registra `run_id` com o ownership token. O coordinator usa `{:coordinator, run_id}`.

O coordinator permanece fora do data path. Hoje ele retém o token e encerra a árvore quando recebe stale ownership correspondente.

## Recovery automático atual

Cada scan:

```text
1. list tokens already owned by current RuntimeNode
2. reconcile local trees
3. claim recoverable running Runs
4. start local trees after commit
```

Claim de recovery:

```sql
WHERE status = 'running'
  AND (owner_node_id IS NULL OR owner heartbeat expired)
ORDER BY updated_at, id
FOR UPDATE SKIP LOCKED
LIMIT 25
```

Runs `pending` ficam fora do scanner até existir RunSnapshot.

Falhas globais usam backoff exponencial. Falhas de startup usam backoff em memória por Run e liberam o token quando não existe árvore local correspondente.

Shutdown normal tenta release best effort e encerra árvores locais. Crash isolado de recovery não libera ownership.

## Data plane futuro

```text
RunSupervisor
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

### SourceBroadway

```text
Read Operation Producer
→ fetch/decode
→ source contract validation
→ SourceIdentity + PayloadHash
→ build Records + Deliveries
→ transaction: Records + N Deliveries + Checkpoint
```

Checkpoint só avança após commit do fan-out durável.

### DestinationBroadway

```text
Postgres Delivery Producer
→ claim available Deliveries
→ load in batch
→ Transformation
→ destination contract validation
→ Broadway batcher
→ Write Operation
→ persist Attempt + Delivery outcome
```

Cada destination possui backlog, concorrência, batching e retries independentes.

### EnrichmentBroadway

Enrichment opcional executa side effects externos antes da Transformation e persiste resultado/status. Definição pertence à PackageVersion; resultado pertence a Executions.

## Retry futuro

Broadway não será scheduler de retry. Delivery retryable volta para:

```text
status = pending
available_at = future timestamp
attempt_count += 1
```

O Producer busca apenas trabalho disponível.

## Fora do desenho inicial

- uma árvore de Run distribuída entre nodes;
- ownership via `:global`, `:pg`, Horde ou CRDT;
- Oban job por Delivery;
- fila externa sem gargalo medido;
- mensagens por Record passando pelo RunCoordinator.
