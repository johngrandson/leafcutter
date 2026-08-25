# Quality gates

## Gate local canônico

```bash
mix quality
```

O alias roda, nesta ordem:

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test
mix dialyzer # ou mix dialyzer --plt enquanto apps/ estiver vazio
```

O gate usa `MIX_ENV=test` para manter Credo e Dialyxir fora das dependências
de runtime. As ferramentas ficam no umbrella root e verificam todas as child
applications.

Enquanto a umbrella não possui child applications, o gate executa
`mix dialyzer --plt`, pois ainda não existem BEAMs do projeto para analisar.
Depois que a primeira application for criada, o mesmo alias passa a executar
`mix dialyzer` automaticamente.

Não existe arquivo de exclusões do Dialyzer. Um warning só deve ser ignorado
depois de confirmar que ele é um falso positivo e documentar o motivo.

## Comandos adicionais

```bash
mix docs
```

`mix docs` exige `ex_doc` como dependency, ainda não adicionada.

O workflow de CI para executar `mix quality` será adicionado separadamente.

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
