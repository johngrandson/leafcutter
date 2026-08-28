# Run ownership, fencing e recovery

- Status decisório: Accepted
- Estado de implementação: MATERIALIZADO

## RuntimeNode

```text
id                 UUID per application incarnation
node_name          metadata, not unique
last_heartbeat_at  PostgreSQL clock
```

Restart isolado de NodeHeartbeat preserva `id`; restart da application cria nova incarnação.

## Run

```text
id
status
owner_node_id | nil
generation >= 0
ownership_acquired_at | nil
```

Constraint: owner e ownership timestamp aparecem juntos.

Estados atuais:

```text
pending
running
completed
failed
cancelled
```

## Claim explícito

```elixir
Runs.claim(run_id, runtime_node_id)
```

- valida claimant existente/ativo;
- locka Run `FOR UPDATE`;
- pending exige RunSnapshot em formato suportado;
- pending sem snapshot retorna `:run_snapshot_not_found`;
- pending com formato desconhecido retorna `:unsupported_run_snapshot_format`;
- running unowned/stale-owned pode ser adquirido independentemente de snapshot;
- primeiro claim elegível muda pending para running;
- nova posse incrementa generation;
- mesmo active owner recebe token idempotente;
- outro active owner é rejeitado.

Token:

```text
run_id
runtime_node_id
generation
```

## Release

```elixir
Runs.release(token)
```

UPDATE inclui os três campos do token. Release preserva status/generation. Repetição é idempotente enquanto não existir claim posterior.

## Supervision local

```text
run_id → RunSupervisor + token
{:coordinator, run_id} → RunCoordinator + token
```

Registry é local.

## Recovery

`RunRecovery`:

- lista tokens owned pela incarnação atual;
- reconstrói árvore ausente sem incrementar generation;
- reclama Runs running sem owner ou com owner expirado;
- inicia Runs pending sem owner quando possuem snapshot em formato suportado;
- exclui pending sem snapshot ou com formato desconhecido;
- usa `FOR UPDATE SKIP LOCKED`, batch 25, ordering `updated_at + id`;
- inicia árvore após commit;
- aplica backoff global e por Run;
- tenta release best effort no shutdown normal.

## Fencing future writes

Toda escrita crítica futura usa o token no mesmo SQL da mutação. Não existe check-then-write separado.
