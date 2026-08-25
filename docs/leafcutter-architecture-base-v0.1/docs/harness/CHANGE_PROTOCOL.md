# Protocolo de mudança

## Unidade de trabalho

Preferir uma mudança por context/capability e um diff pequeno.

## Fluxo

```text
understand
→ decide owner
→ verify ADR
→ write Task Brief
→ developer implements
→ run focused tests
→ review
→ update docs/checkpoint
→ commit
```

## Mudança arquitetural

Quando uma implementação contradiz ADR ou boundary:

1. não contornar silenciosamente;
2. documentar o conflito;
3. propor nova decisão;
4. ratificar;
5. criar/supersede ADR;
6. só então implementar.

## Dependency

Nova dependency exige nota com:

- problema resolvido;
- alternativa nativa avaliada;
- manutenção/maturidade;
- impacto operacional;
- caminho de remoção/troca.
