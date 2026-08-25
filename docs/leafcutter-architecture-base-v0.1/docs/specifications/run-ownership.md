# Run Ownership and Recovery

- Status: Accepted baseline

```text
one Run
→ one owner node
→ one generation
```

## Node heartbeat

Uma linha/registro por BEAM node ativo. Heartbeat expiration autoriza tentativa de recovery.

## Claim

Claim é transação atômica que:

- verifica owner expirado/estado reclaimable;
- define novo owner;
- incrementa generation;
- registra evento de recovery.

## Fencing

Escritas críticas carregam/validam generation. Owner antigo não pode continuar após takeover.

## Distributed Erlang

`nodedown` acelera detecção, mas não concede ownership.
