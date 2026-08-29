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

Ratificado, ainda não materializado:

- behaviours, invocation/result structs e error contract de Operation definidos no ADR-0021;
- paginação opaca e partial-success completo/ordenado definidos no ADR-0021.

Ainda não ratificado:

- behaviour executável de Connector, caso uma necessidade além de Operation apareça;
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

O ADR-0019 controla somente 26A. O ADR-0021 ratifica signatures, structs, paginação, partial success, validação e error contract do Slice 26B, ainda sem materialização em código. Transport HTTP permanece no Slice 26C.
