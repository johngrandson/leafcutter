# ADR-0008 — Connector → Operation → Transport

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO — METADATA DE CONNECTOR/OPERATION

## Decisão

~~~text
Connector  → semântica do sistema externo
Operation  → ação específica
Transport  → protocolo
~~~

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

## Evolução

A fronteira seguinte ao ADR-0018 foi dividida:

~~~text
26A ContractVersion + JSON Schema/JSV
26B Operation executable contract
26C Transport + first HTTP reference Operation
~~~

O ADR-0019 controla somente 26A e não materializa esta decisão além da metadata já existente. Signatures, structs e behaviours de Operation continuam pendentes de ratificação no Slice 26B; Transport HTTP permanece no Slice 26C.
