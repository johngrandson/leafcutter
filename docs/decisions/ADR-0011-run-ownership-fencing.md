# ADR-0011 - Ownership de Run e fencing

- Status: Accepted

## Decisão

Um Run pertence a um BEAM node por vez. Existe um heartbeat por node, não por Run. Run guarda `owner_node` e `generation`.

Cada inicialização da application `leafcutter_runtime` cria um `RuntimeNode.id` novo para representar uma incarnação específica do runtime. Reiniciar apenas o processo `NodeHeartbeat` preserva esse identificador; reiniciar a application ou o BEAM cria outro.

`node_name` registra o valor de `node()` apenas como metadata e não possui unicidade. Duas incarnações diferentes podem reutilizar o mesmo nome sem que o heartbeat novo ressuscite ownership pertencente à incarnação anterior.

Após expiração do heartbeat, outro node pode claimar atomicamente, incrementar `generation` e reconstruir a árvore. Escritas críticas rejeitam generation antiga.

Registry é local. Distributed Erlang sinaliza membership, mas PostgreSQL é a autoridade.

## Consequências

- proteção contra stale owners, restarts e partitions;
- identidade durável não depende somente do nome Erlang reutilizável;
- registros históricos de incarnações antigas podem permanecer para diagnóstico e fencing;
- sem `:global`, `:pg`, Horde ou lock distribuído customizado;
- todas as escritas críticas precisam considerar fencing.
