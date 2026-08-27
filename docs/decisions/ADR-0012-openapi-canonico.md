# ADR-0012 — OpenAPI canônico; Postman derivado

- Status: Accepted
- Estado de implementação: PHOENIX FOUNDATION; OPENAPI NÃO MATERIALIZADO

## Decisão

OpenAPI será a fonte canônica dos contracts HTTP. Postman e SDKs serão derivados.

## Estado atual

`leafcutter_api` possui Endpoint/Router/Telemetry básicos, mas ainda não possui surface de produto nem spec OpenAPI.

## Consequências

Nenhum client derivado pode conter conhecimento exclusivo. SDKs só entram após estabilização do contrato.
