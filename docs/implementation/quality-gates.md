# Quality gates

## Base

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
```

## Quando disponíveis

```bash
mix dialyzer
mix credo --strict
```

Dialyzer/Credo entram com configuração revisada. Não adicionar apenas para marcar uma caixa.

## Runtime

Testes específicos devem validar:

- atomicidade Record/Deliveries/Checkpoint;
- claim concorrente;
- retries e `available_at`;
- partial batch success;
- stale generation;
- crash/restart;
- destination isolation.

## Contracts

- schemas válidos;
- fixtures válidas/inválidas;
- manifest validado;
- source/destination boundaries exercitadas.
