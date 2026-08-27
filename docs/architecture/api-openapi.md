# API e OpenAPI

> **Status: PHOENIX FOUNDATION MATERIALIZADA; API DE PRODUTO E OPENAPI RATIFICADOS — NÃO MATERIALIZADOS.**

## Estado atual

`leafcutter_api` possui:

```text
Phoenix Endpoint
Router
Telemetry
ErrorJSON básico
Bandit adapter
```

Ainda não existem endpoints públicos para Organizations, RBAC, Runs ou demais contexts.

## Direção ratificada

Toda capacidade do produto será operável sem frontend.

```text
OpenAPI canônico
├── documentação da plataforma
├── Postman derivado
└── SDKs futuros após estabilização
```

Postman e SDKs não podem conter regras ou knowledge ausente no contrato canônico.

## Boundary HTTP

Fluxo planejado:

```text
HTTP request
→ authenticate
→ resolve actor
→ Organizations.Access.authorize(...)
→ workflow/context public API
→ map domain result to HTTP
```

Controllers e plugs adaptam transporte; não possuem regra de negócio.

## Erros

Contracts de domínio continuam explícitos. O error envelope HTTP final ainda precisa ser ratificado, incluindo o quanto de lifecycle interno será exposto externamente.

## Health e readiness

Health/readiness completos ainda não foram materializados. A API deverá distinguir processo vivo de dependências realmente prontas, especialmente Repo e runtime.

## Futuro deliberado

- OpenAPI versionado;
- autenticação de User e ServiceAccount;
- endpoints de gestão e execução;
- Postman gerado;
- inbound HTTP sources em release posterior;
- SDKs somente com API estável.
