# Testes e qualidade

> **Status: FOUNDATION MATERIALIZADA E EM USO.**

## Quality gate canônico

```bash
mix quality
```

O alias executa, conforme a configuração atual:

```text
compile --warnings-as-errors
format --check-formatted
credo --strict
test
dialyzer
```

Quando houver migration nova, executar também:

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```

## Cobertura materializada

Os testes atuais cobrem:

- Ecto changesets e constraints;
- lifecycle de Organizations, Environments, Users, ServiceAccounts e Roles;
- memberships, role assignments e permissions;
- authorization para User e ServiceAccount;
- concorrência em operações críticas de domínio;
- RuntimeNode heartbeat;
- Run ownership, release e fencing;
- claim concorrente;
- validação, normalização e imutabilidade de RunSnapshot v1;
- criação atômica de Run + RunSnapshot;
- eligibility de Runs `pending` por formato suportado;
- per-Run supervision;
- RunRecovery, lotes concorrentes e shutdown.

## Estratégia

- testar comportamento observável, não timer refs ou detalhes internos;
- usar SQL Sandbox;
- testar constraints no banco, não apenas changeset;
- incluir concorrência determinística onde row locks e idempotência importam;
- manter typespecs precisos;
- tratar Dialyzer como gate, não sugestão;
- preservar examples de `@doc` executáveis quando dependências permitirem.

## Data plane futuro

Quando Broadway entrar, testes deverão cobrir:

- demand/backpressure;
- batch boundaries;
- durable fan-out atomicity;
- retry scheduling;
- partial success;
- stale ownership em escritas críticas;
- recovery após crash entre efeito externo e commit local.

## Documentação

Mudanças arquiteturais só estão completas quando código, testes, ADRs, specifications e checkpoint concordam sobre o que existe e o que continua futuro.
