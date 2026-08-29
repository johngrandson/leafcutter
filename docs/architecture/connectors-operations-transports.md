# Connectors, Operations e Transports

> **Status: PARCIALMENTE MATERIALIZADO.** Connector, ConnectorVersion e Operation existem como metadata no Catalog. O contract concreto de Operation executável pertence ao Slice 26B; Transport e a primeira referência HTTP pertencem ao Slice 26C.

## Estado materializado

~~~text
Connector
└── immutable ConnectorVersion
    └── Operation metadata
~~~

`Leafcutter.Catalog.Connectors` cria e lê Connector identities e publica ConnectorVersion com suas Operations atomicamente. Operation materializa `ref` e `role: source | destination`; behaviour executável, paginação, requests, responses e Transport não existem no código atual.

## Separação

~~~text
Connector
→ conhece o sistema externo

Operation
→ conhece uma ação específica

Transport
→ conhece o protocolo
~~~

Catalog possui metadata e versões. `leafcutter_connectors` possuirá behaviours e implementações executáveis.

ContractVersion + JSON Schema/JSV é uma boundary anterior e separada, owned pelo Catalog. O Slice 26A ratificado no ADR-0019 não adiciona behaviour ou Transport a `leafcutter_connectors`.

## Slice 26B — Operation executável

Ainda exige ratificação concreta.

Direções conceituais preservadas:

- Read Operation normaliza paginação independentemente de `page`, `offset`, cursor ou `next_url`;
- Write Operation recebe batch já transformado e validado;
- resultado por item preserva sucesso parcial;
- auth/config chegam resolvidos;
- Operation não conhece internals de Organization, Integration, Run ou Transformation;
- pontos source/destination de `Contracts.validate/2` serão explícitos.

Ainda estão abertos signatures, structs, cursor semantics, ordering/completeness de partial results e integração com retry taxonomy.

## Slice 26C — Transport e referência HTTP

HTTP permanece o primeiro Transport planejado. O slice deverá ratificar:

- Transport behaviour;
- request/response boundary;
- primeiro Connector/Operation de referência;
- HTTP client e pool strategy;
- timeout e rate-limit translation.

Database, SFTP e outros transports só entram com demanda real.

## Error taxonomy conceitual

~~~text
validation
authentication
rate_limited
timeout
temporary
permanent
~~~

A taxonomy final e sua representação concreta precisam ser confrontadas com `error-retry-model.md` durante 26B.

## Restrições

- não criar GenServer por Connector sem lifecycle real;
- não esconder Transformation dentro da Operation;
- não persistir secrets em Connector metadata;
- não acoplar runtime genérico a detalhes de HTTP;
- não implementar múltiplos transports por antecipação;
- não introduzir Operation/Transport durante a materialização do Slice 26A.
