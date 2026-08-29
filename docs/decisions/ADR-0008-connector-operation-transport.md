# ADR-0008 — Connector → Operation → Transport

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO — METADATA + OPERATION; TRANSPORT PENDENTE

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

Materializado em `leafcutter_connectors`:

- behaviours, invocation/result structs e error contract de Operation definidos no ADR-0021;
- paginação opaca, partial-success completo/ordenado, redaction e invariantes puras.

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

O ADR-0019 controla somente 26A. O ADR-0021 controla signatures, structs, paginação, partial success, validação e error contract materializados no Slice 26B. Transport HTTP permanece no Slice 26C.
