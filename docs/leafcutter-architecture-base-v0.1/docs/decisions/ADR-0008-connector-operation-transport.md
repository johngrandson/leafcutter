# ADR-0008 - Connector, Operation e Transport

- Status: Accepted

## Decisão

```text
Connector → sistema
Operation → ação
Transport → protocolo
```

Read Operations normalizam `records`, `next_cursor`, `done?`. Write Operations recebem batches e preservam resultado por item. HTTP é o primeiro Transport.

## Consequências

- runtime protocol-agnostic;
- connectors conhecidos escondem paginação/auth/rate limits;
- Generic HTTP cobre APIs simples;
- outros Transports entram sem redesenhar o domínio.
