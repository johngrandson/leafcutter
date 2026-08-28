# Primeiro milestone — foundation confiável

- Estado: CONCLUÍDO

## Objetivo original

Estabelecer boundaries, persistência compartilhada, tenancy/RBAC e authority durável suficiente para iniciar Runs sem depender de estado efêmero.

## Entregue

```text
four OTP applications
one Repo + PubSub + Oban
Organizations/RBAC
RuntimeNode heartbeat
Run ownership + generation
local per-Run supervision
automatic recovery
quality gates and harness
```

## Não fazia parte do milestone

```text
RunSnapshot
Catalog
Connections
Integrations
Connectors
Broadway data plane
OpenAPI product surface
```

Esses elementos não pertenciam ao milestone. RunSnapshot, Catalog, Connections, Integration e EnvironmentDeployment foram materializados em slices posteriores; connectors executáveis, Broadway e OpenAPI de produto permanecem futuros.

## Resultado

O projeto encerrou este milestone com um control plane real e testado. O milestone posterior, também concluído, transformou Run de identity/ownership record em execução definida por snapshot imutável.
