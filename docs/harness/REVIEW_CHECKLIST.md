# Checklist de review

## Estado e escopo

- [ ] O diff implementa apenas o slice autorizado.
- [ ] O comportamento descrito como atual existe no código/testes.
- [ ] A arquitetura futura ratificada não foi apagada.
- [ ] Decisão aberta não foi fechada por inferência.

## Boundaries

- [ ] Context owner correto.
- [ ] Nenhum acesso a internals de outro context.
- [ ] Workflow cross-context está na application layer adequada.
- [ ] Nenhuma app/processo/abstração nova sem boundary/lifecycle real.

## Durabilidade e concorrência

- [ ] Authority durável está no PostgreSQL quando necessário.
- [ ] Idempotência e retries têm semântica explícita.
- [ ] Row locks/transações são curtos e justificados.
- [ ] Toda escrita crítica de Run aplica fencing token na própria mutação.
- [ ] Crash/restart/replay foram considerados.

## Contracts

- [ ] `@moduledoc`, `@doc`, `@typedoc` e `@spec` corretos.
- [ ] Typespecs possuem shapes precisas.
- [ ] Erros públicos são previsíveis.
- [ ] Raw secrets não aparecem em docs/logs/snapshots indevidos.

## Testes e gates

- [ ] Happy path e failure paths.
- [ ] Constraints de banco.
- [ ] Concorrência determinística quando relevante.
- [ ] `mix quality` passa conforme
  `docs/implementation/quality-gates.md`.

## Documentação

- [ ] ADR/specification atualizados quando necessário.
- [ ] `estado-atual-e-visao-futura.md` continua correto.
- [ ] `CURRENT.md` avançou se houve milestone.
