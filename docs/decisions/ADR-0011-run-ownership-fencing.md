# ADR-0011 — Ownership de Run e fencing

- Status: Accepted
- Estado de implementação: MATERIALIZADO

## Decisão

Um Run pertence a uma RuntimeNode incarnação por vez. Existe um heartbeat por incarnação, não por Run. `generation` é fencing token monotônico.

## Estado atual

Materializado:

```text
runtime_nodes
runs.owner_node_id
runs.generation
claim/release
RunRegistry local
RunSupervisor + RunCoordinator
RunRecovery polling
FOR UPDATE SKIP LOCKED
```

O relógio do PostgreSQL decide liveness. Reclaim incrementa generation. Release usa o token no mesmo UPDATE.

## Recovery

O scanner reconstrói árvores já owned sem incrementar generation, reclama Runs `running` sem owner ou com owner expirado e inicia Runs `pending` com RunSnapshot em formato suportado.

Falhas operacionais representadas no contrato de recovery e exceções esperadas de conexão ou operação PostgreSQL entram no backoff global. Erros de programação não são convertidos em falhas retryable: o processo encerra e sua supervisão aplica a política de restart.

## Consequências

- stale owners são rejeitados;
- Registry não é authority distribuída;
- sem `:global`, `:pg`, Horde ou lock customizado;
- toda escrita crítica futura inclui o token na própria mutação.
