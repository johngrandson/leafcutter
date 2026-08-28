# ADR-0008 — Connector → Operation → Transport

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO — METADATA DE CONNECTOR/OPERATION

## Decisão

```text
Connector  → semântica do sistema externo
Operation  → ação específica
Transport  → protocolo
```

HTTP será o primeiro Transport.

## Estado atual

Materializado no Catalog:

- Connector como identidade global;
- ConnectorVersion imutável;
- Operation metadata com `ref` e role source/destination;
- publicação atômica e sealing no PostgreSQL.

Ainda não materializado:

- behaviours executáveis de Connector e Operation;
- paginação e partial-success contracts;
- Transport e implementação HTTP.

## Consequências

- runtime genérico não conhece detalhes de HTTP/vendor;
- Read Operations normalizam paginação;
- Write Operations preservam partial success;
- outros transports entram somente com necessidade real.
