---
title: "Como o Leafcutter foi arquitetado"
subtitle: "Estado materializado, decisões ratificadas e evolução planejada"
author: "Leafcutter Architecture"
date: "28 de agosto de 2026"
lang: pt-BR
toc: true
toc-depth: 3
numbersections: true
geometry: margin=2.2cm
fontsize: 11pt
mainfont: "DejaVu Sans"
monofont: "DejaVu Sans Mono"
colorlinks: true
linkcolor: blue
urlcolor: blue
---

# Introdução

O Leafcutter é uma plataforma para construir e operar integrações confiáveis entre sistemas.

```text
System A
   ↓ extract once
validated data
   ├── transform for System B → batch → deliver to B
   └── transform for System C → batch → deliver to C
```

O produto final precisa lidar com contratos diferentes, paginação, rate limits, partial success, identidades incompatíveis, retries, grandes volumes e falha de processos/nodes.

A implementação atual ainda não executa esse fluxo completo. Ela construiu primeiro as foundations de tenancy, autorização, durabilidade de ownership e recovery necessárias para o data plane posterior.

# Como ler este documento

```text
MATERIALIZADO
→ existe no código e testes

RATIFICADO
→ direção aprovada para próximos slices

ABERTO
→ ainda precisa de decisão explícita
```

A visão futura não é apagada pela implementação incremental. Ao mesmo tempo, diagramas futuros não descrevem o código atual.

# Princípios

## Menor primitive correta

```text
Elixir/Erlang
→ OTP
→ Phoenix/Ecto/PubSub/Broadway/Oban
→ plain function/module
→ custom abstraction only when necessary
```

OTP existe para lifecycle e concorrência reais. Transformation será função pura. Broadway será o data plane. PostgreSQL é authority durável.

## Estado operacional e durável

```text
OTP
→ what is happening now

PostgreSQL
→ how to recover after everything disappears
```

Essa separação já é concreta em RuntimeNode, Run ownership, generation e RunRecovery.

## At-least-once

O Leafcutter não promete exactly-once entre sistemas que não compartilham transação. Repetição é esperada quando o efeito externo não pode ser provado.

# Estrutura materializada

## Umbrella

```text
leafcutter_core
leafcutter_connectors
leafcutter_runtime
leafcutter_api
```

Core hospeda Organizations, Catalog, Connections e Integrations mínimos, além de Repo, PubSub e Oban. Connectors é uma boundary ainda vazia. Runtime hospeda Executions foundation e OTP control plane. API é Phoenix API-only foundation.

## Organizations e autorização

```text
Organization
├── Environment
├── User → Membership
├── ServiceAccount
└── Role + Permission
```

Roles podem ser organization-wide ou environment-scoped. User e ServiceAccount possuem assignment models separados, preservando FKs e tipos explícitos.

Authorization recebe actor e scope explícitos. Não existe `Principal` persistido.

## Catalog parcial

```text
Connector
└── ConnectorVersion
    └── Operation

Contract
└── ContractVersion

Package
└── PackageVersion
    └── PackageVersionEndpoint
```

ConnectorVersion e Operations são publicados na mesma transação. PostgreSQL impede versões sem sealing e rejeita append, update ou delete do conteúdo publicado. ContractVersion nasce publicada com schema Draft 2020-12 object/boolean, validado e construído com JSV, e também é imutável; versões identity-only anteriores permanecem históricas. PackageVersion e seus endpoints relacionais são publicados atomicamente, preservam uma source e destinations ordenadas, rejeitam ContractVersions legadas em novas publicações e recebem a mesma proteção de sealing e imutabilidade.

## RuntimeNode

Cada startup da application runtime gera uma nova identidade UUID. Restart isolado do heartbeat preserva a identidade; restart da application cria nova incarnação.

O heartbeat é persistido antes de Telemetry. PostgreSQL fornece o relógio usado em liveness e ownership.

## Run ownership e fencing

`Run` começa com lifecycle mínimo:

```text
pending
running
completed
failed
cancelled
```

```text
owner_node_id
generation
ownership_acquired_at
```

Claim usa row lock. Outro owner só pode assumir quando o owner anterior está ausente ou expirado. Cada nova posse incrementa generation.

Toda escrita crítica futura deverá incluir o ownership token no mesmo comando SQL da mutação.

## Árvore local por Run

```text
RunDynamicSupervisor
└── RunSupervisor
    └── RunCoordinator
```

O coordinator atual retém token e reage a stale ownership. Ele não recebe dados por Record.

## Recovery automático

```text
RunRecovery
→ poll PostgreSQL
→ reconcile tokens already owned locally
→ claim running recoverable Runs and eligible pending Runs
→ FOR UPDATE SKIP LOCKED
→ start local trees after commit
```

O scanner materializado inicia Runs `pending` somente quando possuem RunSnapshot em formato suportado. Presença e versão provam eligibility no control plane, não executabilidade semântica completa. Runs legadas `running` preservam recovery independentemente do snapshot.

Falhas operacionais retornadas pelo contrato de recovery e exceções esperadas de banco usam backoff global. Erros de programação encerram o processo e são tratados pela supervisão, evitando retries silenciosos de defeitos determinísticos.

# A plataforma-alvo ratificada

## Package, Integration e Run

```text
PackageVersion
→ reusable executable definition

EnvironmentDeployment
→ environment-specific configuration

RunSnapshot
→ immutable resolved definition

Run
→ concrete execution
```

Essa separação impede que mudança de configuração altere uma Run em andamento ou histórica. RunSnapshot v1, EnvironmentDeployment e o resolver transacional estão materializados. Cada nova resolução congela o estado atual sem alterar snapshots anteriores.

## Catalog

Catalog já controla identidades e versões de Connectors, Contracts e Packages, além das Operations e da topologia relacional de PackageVersion. O ADR-0023 ratifica Manifest v1 e a binding de build sem mover execução para o Catalog. Availability e a materialização do build permanecem posteriores.

## Connections

Connections já controla acesso configurado mínimo a sistemas externos por Connection environment-scoped, config não sensível e binding exato para SecretVersion imutável. Organization/Environment ativos são protegidos por locks e integridade relacional. Raw secrets não são persistidos. OAuth durable state, providers e rotation continuam futuros.

## Integrations

Integration já é uma identidade lógica materializada dentro da Organization. EnvironmentDeployment seleciona PackageVersion, promotable/local config e bindings completos por Environment. Triggers continuam futuros.

Promotion levará estado promovível aprovado sem copiar credenciais ou config local.

# Data contracts e external systems

## JSON Schema

Source e destination payloads serão validados com JSON Schema Draft 2020-12 via JSV.

O ADR-0019 ratifica a boundary de ContractVersion executável, publicação, compilação e validação do Slice 26A. O slice está materializado por PackageVersion, EnvironmentDeployment e pelo resolver de Run, que repetem a proteção contra versões legadas. O ADR-0021 ratifica a validação source depois da Read Operation e a validação destination depois da Transformation, antes da Write Operation.

```text
external source
→ source ContractVersion
→ trusted map
→ Transformation
→ destination ContractVersion
→ external destination
```

## Connector, Operation e Transport

```text
Connector
→ system semantics

Operation
→ one action

Transport
→ protocol
```

O ADR-0021 controla os Read/Write behaviours síncronos materializados. O ADR-0022 controla o primeiro Transport HTTP bounded. O ADR-0023 ratifica Manifest/build/module resolution em 26C2; a primeira referência real permanece separada em 26C3.

# Transformation, Enrichment e Interceptor

Transformation será pura e suportará 1→0/1/N.

Enrichment será side effect explícito e durável antes da Transformation.

Interceptor adaptará request/protocolo sem esconder regra de negócio.

# Data plane futuro

```text
RunSupervisor
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

## Source

```text
fetch
→ validate source
→ SourceIdentity + PayloadHash
→ persist Records + Deliveries + Checkpoint atomically
```

## Destinations

Cada destination consumirá seu backlog independente, transformará, validará, fará batch, chamará Operation e persistirá Attempt/Delivery outcome.

Um destino lento não bloqueia os demais.

## Retry

Delivery retryable volta para pending com `available_at` futuro. Broadway controla demand e batching; não será scheduler de retry.

## Sem fila externa inicial

PostgreSQL será o durable backlog inicial. Uma external queue só entra com gargalo medido.

# Cluster

Uma Run tree permanece em um node. Todos os nodes usarão inicialmente a mesma release.

Distributed Erlang pode oferecer membership e sinais rápidos, mas PostgreSQL continua sendo a authority. Registry é local.

# API e governança

A plataforma será API-first, com OpenAPI canônico e Postman derivado.

RBAC já existe como foundation. Homologation, promotion, rollback, secret rotation, payload access e AuditEvent continuam futuros ratificados.

# Observabilidade e storage

Heartbeat Telemetry já existe. O data plane adicionará throughput, backlog, retry e external latency metrics.

PostgreSQL armazena operational truth. JSONB pode simplificar a primeira versão. Object storage e analytics store ficam condicionados a volume/custo.

# O que está aberto

RunSnapshot v1, as authorities upstream, ContractVersion, Operation executável e o Transport
HTTP bounded estão materializados sem alterar o snapshot. Os passos 35–36 de 26C2 materializam
Manifest, binding compilada e persistência do digest; build inventory e resolução em runtime
continuam pendentes. Permanecem abertos os lifecycles ampliados, rolling upgrade,
idempotência/invocation durável, retenção, primeira referência real, data plane, secrets
concretos, OpenAPI e infraestrutura de produção.

# Conclusão

O Leafcutter já possui uma base real de tenancy, autorização, Catalog, Connections, Integrations, EnvironmentDeployments e runtime recovery. A arquitetura completa preservada nos documentos descreve a evolução para uma plataforma de integração, não uma afirmação de que Broadway, build de Integration Packages e Records já existem.

```text
present
→ RBAC + authorities upstream + transactional resolution + ownership + recovery + RunSnapshot v1
→ ContractVersion + JSON Schema/JSV + enforcement em PackageVersion/Deployment/Run
→ Operation Read/Write behaviours + in-memory validation (26B)
→ bounded HTTP Transport + supervised Finch HTTP/1 pool (26C1)
→ Manifest v1 + compiled Read/Write binding + persisted digest (26C2, passos 35–36)

next
→ materializar build inventory e resolver modules (26C2, passos 37–38)

future
→ durable Broadway integration data plane
```

Essa separação mantém a visão ambiciosa sem sacrificar honestidade arquitetural nem simplicidade incremental.
