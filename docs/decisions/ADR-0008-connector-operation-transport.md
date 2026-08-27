# ADR-0008 — Connector → Operation → Transport

- Status: Accepted
- Estado de implementação: NÃO MATERIALIZADO

## Decisão

```text
Connector  → semântica do sistema externo
Operation  → ação específica
Transport  → protocolo
```

HTTP será o primeiro Transport.

## Consequências

- runtime genérico não conhece detalhes de HTTP/vendor;
- Read Operations normalizam paginação;
- Write Operations preservam partial success;
- outros transports entram somente com necessidade real.
