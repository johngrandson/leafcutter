# API-first, OpenAPI e Postman

## Decisão

Toda capacidade do Leafcutter deve ser operável sem frontend.

OpenAPI é a fonte canônica do contrato da API. Postman é uma Collection gerada/sincronizada a partir dela.

```text
OpenAPI
├── documentation
├── Postman collection
└── SDKs futuros
```

## Domínios esperados na API

```text
Authentication
Organizations
Users / Service Accounts / RBAC
Environments
Catalog
Contracts
Packages / Package Versions
Connections / Secrets metadata
Integrations
Homologations / Promotions / Rollbacks
Triggers / Schedules
Runs
Records
Deliveries
Attempts
Enrichments
IdentityMappings
Notification Rules
Audit
```

## Workflows

A API deve permitir workflows completos, não apenas CRUD:

```text
create Organization
→ create HML and PROD environments
→ create Connections
→ publish Package Version
→ configure Integration in HML
→ execute and inspect
→ homologate
→ promote
→ execute in PROD
```

## Commands

Ações de domínio podem usar endpoints explícitos:

```text
POST /integrations/{id}/activate
POST /integrations/{id}/runs
POST /runs/{id}/pause
POST /deliveries/{id}/retry
POST /deployments/{id}/promote
```

A nomenclatura final ainda precisa ser desenhada no OpenAPI.

## Idempotency

Endpoints que criam efeitos relevantes devem aceitar Idempotency-Key quando apropriado.

## Paginação e erros

Paginação, filtros, sorting e error envelope devem ser consistentes em toda a API.

## SDKs

SDKs só entram depois que endpoints, errors e workflows estabilizarem. Não devem influenciar a arquitetura da primeira versão.

## Inbound API

Inbound Endpoints são sources HTTP declarativos de Integration Packages. A OpenAPI das APIs inbound é separada da OpenAPI administrativa da plataforma.
