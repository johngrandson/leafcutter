# ADR-0008 — Connector → Operation → Transport

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO — METADATA + OPERATION + HTTP 26C1 + 26C2/PASSO 35

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
- paginação opaca, partial-success completo/ordenado, redaction e invariantes puras;
- Manifest v1 bounded e binding compilada de refs para módulos Read/Write literais.

Materializado conforme o ADR-0022:

- facade/Adapter HTTP-specific;
- Request/Response/Error bounded;
- Finch HTTP/1 com pool supervisionado e uma tentativa por chamada.

Parcialmente materializado conforme o ADR-0023:

- Manifest e binding compilada existem no passo 35;
- persistência do digest, build inventory e resolução em runtime permanecem nos passos 36–38.

Ainda não ratificado:

- behaviour executável de Connector, caso uma necessidade além de Operation apareça;
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

O ADR-0019 controla 26A, o ADR-0021 controla 26B e o ADR-0022 controla 26C1, todos
materializados. O ADR-0023 controla 26C2 sem registry implícito; o passo 35 está materializado
e a referência real permanece em 26C3.
