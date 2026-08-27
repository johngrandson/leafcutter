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

O scanner reconstrói árvores já owned sem incrementar generation e reclama Runs `running` sem owner ou com owner expirado.

## Consequências

- stale owners são rejeitados;
- Registry não é authority distribuída;
- sem `:global`, `:pg`, Horde ou lock customizado;
- toda escrita crítica futura inclui o token na própria mutação.
