# Visão geral da arquitetura

## O problema que o Leafcutter resolve

O Leafcutter conecta sistemas com estruturas e regras diferentes.

```text
System A
   ↓ extract once
validated source data
   ├── transform for System B → batch → deliver to B
   └── transform for System C → batch → deliver to C
```

Cada destino pode ter:

- contrato próprio;
- transformação própria;
- batching próprio;
- rate limit próprio;
- concorrência própria;
- retries independentes;
- falhas isoladas.

## As peças principais

```text
Organization
└── Environment
    ├── Connections
    ├── Integrations
    └── Runs

Catalog
├── Connectors
├── Operations
├── Contracts
└── Integration Packages

Integration Package
├── manifest.json
├── JSON Schemas
├── Transformations
├── optional Enrichments
└── Interceptors

Run
├── Run Coordinator
├── Source Broadway
├── optional Enrichment Broadways
└── Destination Broadways
```

## Control plane e data plane

```text
CONTROL PLANE
OTP processes
- start
- pause
- resume
- cancel
- recover
- coordinate lifecycle

DATA PLANE
Broadway pipelines
- fetch
- validate
- persist durable fan-out
- transform
- enrich
- batch
- deliver
```

## Durabilidade

O fan-out inicial é persistido:

```text
Record
├── Delivery B pending
└── Delivery C pending
```

O checkpoint só avança na mesma transação que persiste o lote de Records e todas as Deliveries.

## Cluster

Um Run pertence a um node por vez. O node executa a árvore inteira do Run localmente. PostgreSQL determina ownership e recovery; Distributed Erlang melhora comunicação e detecção, mas não é a autoridade durável.

## API

Toda capacidade deve ser operável sem frontend. OpenAPI é a fonte canônica da API. Postman é um espelho derivado. SDKs entram somente depois da estabilização do contrato.
