# ADR-0008 — Connector → Operation → Transport

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO — METADATA + OPERATION; HTTP RATIFICADO

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

Ratificado no ADR-0022, ainda não materializado:

- facade/Adapter HTTP-specific;
- Request/Response/Error bounded;
- Finch HTTP/1 com pool supervisionado e uma tentativa por chamada.

Ainda não ratificado:

- behaviour executável de Connector, caso uma necessidade além de Operation apareça;
- Package Manifest/build binding e module resolution (26C2);
- primeira Operation HTTP real e vendor mapping (26C3).

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
26C1 HTTP Transport boundary + Finch adapter
26C2 Package Manifest/build binding + module resolution
26C3 first production reference Operation
~~~

O ADR-0019 controla 26A e o ADR-0021 controla 26B, ambos materializados. O ADR-0022 ratifica 26C1 e impede antecipar 26C2 por registry implícito. A referência real permanece em 26C3.
