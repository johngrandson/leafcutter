# Visão geral da arquitetura

> **Status: PARCIALMENTE MATERIALIZADO.** O documento mostra primeiro o sistema existente e depois a plataforma-alvo ratificada.

## O problema

O Leafcutter conecta sistemas com contratos, identidades, autenticação e comportamento operacional diferentes.

```text
System A
   ↓ extract once
validated source data
   ├── transform for System B → batch → deliver to B
   └── transform for System C → batch → deliver to C
```

Cada destino precisa evoluir e falhar de forma independente.

## O que existe hoje

### Domínio e RBAC

```text
Organization
├── Environments
├── Users + Memberships
├── ServiceAccounts
└── Roles + Permissions + scoped assignments
```

### Catalog parcial

```text
Connector
└── immutable ConnectorVersion
    └── Operations

Contract
└── immutable ContractVersion

Package
└── immutable PackageVersion
    └── ordered PackageVersionEndpoints
```

ConnectorVersion e suas Operations são publicadas atomicamente. Novas ContractVersions publicam schema Draft 2020-12 object/boolean, validado e construído com JSV, e expõem compile/validate; versões identity-only legadas permanecem históricas. PackageVersion publica atomicamente uma source e destinations ordenadas, pinando Operation e ContractVersion em endpoints relacionais imutáveis e rejeitando versões legadas em novas publicações.

O Slice 26A está materializado conforme o ADR-0019, a boundary executável de Operation do
Slice 26B conforme o ADR-0021 e o Transport HTTP bounded de 26C1 conforme o ADR-0022. Os passos
35–36 de 26C2 materializam Manifest, binding compilada e digest persistido conforme o ADR-0023;
inventory e resolução em runtime permanecem pendentes. A primeira referência continua em
26C3.

### Connections mínimo

```text
Environment
├── Connections
└── Secrets
    └── immutable SecretVersions
```

Connection referencia Connector estável, mantém config não sensível e pode selecionar uma SecretVersion exata. APIs públicas protegem scope ativo com locks compartilhados; constraints compostas e triggers preservam Organization/Environment, config JSON object, binding compatível e imutabilidade de SecretVersion.

### Integrations mínimo

```text
Organization
└── Integration
    └── EnvironmentDeployment
        └── EnvironmentDeploymentBinding
```

Integration referencia Package estável. EnvironmentDeployment seleciona PackageVersion, promotable/local config e o conjunto completo de Connections por endpoint. Create e replace validam authorities ativas e ContractVersions executáveis sob locks determinísticos e persistem o agregado atomicamente.

`LeafcutterRuntime.Runs.create_from_deployment/1` resolve esse estado por APIs públicas dentro de uma única transação, revalida ContractVersions executáveis e congela PackageVersion, ContractVersions, destination order, effective config, Connection configs e SecretVersion IDs em uma nova RunSnapshot v1.

### Runtime

```text
EnvironmentDeployment
        ↓
transactional resolution
        ↓
Run + immutable RunSnapshot
        ↓
claim against active RuntimeNode heartbeat
        ↓
Run ownership + generation
        ↓
RunRecovery
        ↓
RunSupervisor
└── RunCoordinator
```

PostgreSQL decide ownership e recovery. Registry e processos OTP representam somente o estado local da incarnação atual.

### Applications

```text
core       → Organizations + Catalog mínimo + Connections mínimo + Integrations mínimo + Repo + PubSub + Oban
connectors → boundary executável ainda vazia
runtime    → Executions foundation + deployment resolution + OTP runtime
api        → Phoenix API-only foundation
```

## Plataforma-alvo ratificada

```text
Organization
└── Environment
    ├── Connections
    ├── EnvironmentDeployments
    └── Runs

Catalog
├── Connectors + Versions
├── Operations
├── Contracts + Versions
└── Packages + Versions

Run
├── immutable RunSnapshot
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

## Control plane e data plane

Atual:

```text
CONTROL PLANE MATERIALIZADO
- durable node liveness
- claim/release
- generation fencing
- local per-Run supervision
- polling recovery de Runs running e pending elegíveis
- criação atômica de Run + RunSnapshot v1
- criação transacional de Run a partir de EnvironmentDeployment
```

Futuro ratificado:

```text
DATA PLANE BROADWAY
- source fetch and validation
- durable Record + Delivery fan-out
- transformation and enrichment
- batching and delivery
- retry and checkpoint
```

## Durabilidade

Hoje, liveness e ownership já são duráveis.

No data plane futuro:

```text
Record
├── Delivery B pending
└── Delivery C pending
```

Records, Deliveries e Checkpoint serão persistidos atomicamente antes de o source avançar.

## Cluster

Uma Run tree permanece em um único node. RuntimeNodes expiram por heartbeat. Outro node pode reclaimar uma Run com nova `generation`. Não há authority em `:global`, Horde ou Registry distribuído.

## API

A application Phoenix existe, mas autenticação, OpenAPI completo e endpoints de produto ainda são futuros ratificados. Toda capacidade deverá ser operável sem frontend.
