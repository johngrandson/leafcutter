# Atualização de estado — 26 de agosto de 2026

- Estado: PESQUISA NÃO NORMATIVA — SNAPSHOT DATADO

Este documento complementa o estudo Twelve-Factor produzido em 25 de agosto de 2026.
Os arquivos `01` a `04` preservam o snapshot e a argumentação originais; eles não
foram retroativamente reescritos para acompanhar a evolução do repositório.

Para o estado atual do Leafcutter, consulte primeiro:

1. `../../checkpoint/CURRENT.md`;
2. `../../architecture/estado-atual-e-visao-futura.md`;
3. código e testes materializados.

## O que mudou desde a pesquisa original

A pesquisa inicial foi escrita quando várias boundaries ainda estavam em ratificação
e o runtime de domínio ainda não havia sido materializado.

### Materializado até esta data

```text
4 OTP applications
application dependency graph
shared Repo + PubSub + Oban
Organizations / Environment / RBAC
RuntimeNode durable heartbeat
Run lifecycle / ownership / fencing
RunRegistry / RunDynamicSupervisor
RunSupervisor / RunCoordinator
RunRecovery polling + SKIP LOCKED
quality gate over the real umbrella applications
Phoenix API-only shell
```

### Ratificado, mas ainda futuro nesta data

```text
operational release/deploy pipeline
complete runtime configuration contract
production CI/deploy
Catalog / Connections / Integrations
RunSnapshot
JSON Schema + JSV
Connector / Operation / Transport runtime
Broadway data plane
durable fan-out
OpenAPI product surface
Notifications / Audit
multi-node production deployment
```

## Releitura dos fatores

| Fator | Estado atualizado em 26/08/2026 |
|---|---|
| I — Codebase | Monorepo/umbrella evidenciado; provenance de deploy/release ainda futura. |
| II — Dependencies | Mix dependencies, lockfile e app dependencies materializados; target de build do produto ainda futuro. |
| III — Config | Configuração de desenvolvimento e teste existe; runtime config de deploy e secrets provider continuam abertos. |
| IV — Backing services | PostgreSQL e Repo materializados; Connections externas permanecem futuras. |
| V — Build, release, run | Build local existe; release imutável e deploy de produção ainda não. |
| VI — Processes | Forte evidência: processos OTP reconstruíveis com ownership e recovery no PostgreSQL. |
| VII — Port binding | Phoenix Endpoint existe como shell; binding, probes e operação de produção ainda futuros. |
| VIII — Concurrency | Concorrência de ownership/recovery materializada; data plane Broadway ainda futuro. |
| IX — Disposability | Foundation de recovery e shutdown por Run materializada; drain do data plane ainda futuro. |
| X — Dev/prod parity | Ainda não comprovada operacionalmente. |
| XI — Logs | Logger e Telemetry existem; contrato de observabilidade de produção ainda futuro. |
| XII — Admin processes | Migrations existem no workflow de desenvolvimento; one-offs da release ainda futuros. |

## Regra de uso

Não use afirmações temporais dos arquivos `01` a `04`, como “as applications ainda
não existem”, como fonte de verdade sobre o repositório atual. O valor desses arquivos
é a análise conceitual dos fatores dentro do contexto em que foram escritos.

Este arquivo também é histórico. Quando houver divergência, prevalecem o código, os
testes, os ADRs aceitos e os documentos canônicos atuais.