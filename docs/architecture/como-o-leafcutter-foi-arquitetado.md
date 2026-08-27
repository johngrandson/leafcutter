---
title: "Como o Leafcutter foi arquitetado"
subtitle: "Estado materializado, decisões ratificadas e evolução planejada"
author: "Leafcutter Architecture"
date: "26 de agosto de 2026"
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

Core hospeda Organizations, Repo, PubSub e Oban. Connectors é uma boundary ainda vazia. Runtime hospeda Executions foundation e OTP control plane. API é Phoenix API-only foundation.

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
→ claim running recoverable Runs
→ FOR UPDATE SKIP LOCKED
→ start local trees after commit
```

O scanner não inicia Runs `pending`, pois ainda não existe RunSnapshot que prove que a linha representa definição executável completa.

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

Essa separação impede que mudança de configuração altere uma Run em andamento ou histórica.

## Catalog

Catalog controlará identidade, versões, publicação e disponibilidade de Connectors, Contracts e Packages. Não executará artefatos.

## Connections

Connections controlará acesso configurado a sistemas externos, incluindo SecretVersion e OAuth durable state. Raw secrets não entrarão no snapshot.

## Integrations

Integration será identidade lógica dentro da Organization. EnvironmentDeployment selecionará PackageVersion, bindings, configs e Triggers por Environment.

Promotion levará estado promovível aprovado sem copiar credenciais ou config local.

# Data contracts e external systems

## JSON Schema

Source e destination payloads serão validados com JSON Schema Draft 2020-12 via JSV.

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

HTTP será o primeiro Transport. Read Operations normalizarão paginação; Write Operations preservarão resultado por item.

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

A próxima decisão é RunSnapshot. Depois permanecem abertos schemas de Catalog/Connections/Integrations, Package Manifest, build de packages, contracts executáveis, data plane, lifecycle completo, secrets, OpenAPI e infraestrutura de produção.

# Conclusão

O Leafcutter já possui uma base real de tenancy, autorização e runtime recovery. A arquitetura completa preservada nos documentos descreve a evolução para uma plataforma de integração, não uma afirmação de que Broadway, Packages, Connections e Records já existem.

```text
present
→ RBAC + ownership + supervision + recovery

next
→ immutable executable Run definition

future
→ durable Broadway integration data plane
```

Essa separação mantém a visão ambiciosa sem sacrificar honestidade arquitetural nem simplicidade incremental.
