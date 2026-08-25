# Primeiro marco - Foundation

## Objetivo

Criar uma base compilável e documentada sem antecipar o domínio.

## Inclui

- umbrella vazia;
- docs e ADRs no repositório;
- `AGENTS.md` e checkpoint;
- CI mínimo;
- formatter configuration;
- ratificação dos contexts/apps;
- criação apenas das apps aprovadas;
- smoke tests das applications;
- ExDoc inicial.

## Não inclui

- Integration domain completo;
- Broadway pipelines;
- Connector framework;
- frontend;
- fila externa;
- cluster multi-node;
- secrets production-grade.

## Definition of done

- `mix format --check-formatted` passa;
- `mix compile --warnings-as-errors` passa;
- `mix test` passa;
- `mix docs` gera documentação;
- dependency graph está documentado;
- `CURRENT.md` aponta o próximo vertical slice.
