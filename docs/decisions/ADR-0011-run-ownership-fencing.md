# ADR-0011 - Ownership de Run e fencing

- Status: Accepted

## Decisão

Um Run pertence a um BEAM node por vez. Existe um heartbeat por node, não por Run. Run guarda `owner_node` e `generation`.

Após expiração do heartbeat, outro node pode claimar atomicamente, incrementar `generation` e reconstruir a árvore. Escritas críticas rejeitam generation antiga.

Registry é local. Distributed Erlang sinaliza membership, mas PostgreSQL é a autoridade.

## Consequências

- proteção contra stale owners e partitions;
- sem `:global`, `:pg`, Horde ou lock distribuído customizado;
- todas as escritas críticas precisam considerar fencing.
