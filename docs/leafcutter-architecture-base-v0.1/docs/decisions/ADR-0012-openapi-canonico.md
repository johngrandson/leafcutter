# ADR-0012 - OpenAPI canônico

- Status: Accepted

## Decisão

A plataforma é API-first. OpenAPI é a fonte canônica da API administrativa e, separadamente, das Inbound APIs. Postman é derivado/sincronizado. SDKs entram após estabilização.

## Consequências

- nenhum conhecimento exclusivo no Postman;
- documentação e testes de contrato deriváveis;
- frontend futuro é outra interface sobre a mesma API;
- exige disciplina de examples/errors/operationId/tags.
