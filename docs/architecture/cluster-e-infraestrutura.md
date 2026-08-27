# Cluster e infraestrutura

> **Status: MODELO DISTRIBUÍDO PARCIALMENTE MATERIALIZADO.** A authority no PostgreSQL existe; discovery e deployment multi-node concretos continuam futuros.

## Unidade de execução

Uma árvore de Run permanece em um único node:

```text
Node A
└── RunSupervisor
    └── RunCoordinator
```

No futuro, as pipelines Broadway da mesma Run também permanecem nesse node inicialmente.

## Identidade de runtime

Cada startup da application gera um UUID:

```text
application start
→ new RuntimeNode id

NodeHeartbeat restart
→ same RuntimeNode id

BEAM/application restart
→ new RuntimeNode id
```

`node_name` não possui unicidade e não pode reviver ownership antigo.

## Authority

```text
PostgreSQL
→ liveness, ownership, generation and recovery

Registry
→ local process lookup

Distributed Erlang
→ optional operational signal and communication
```

Não usar Distributed Erlang como banco, fila durável ou lock authority.

## Recovery concorrente

Nodes podem escanear simultaneamente. `FOR UPDATE SKIP LOCKED` distribui lotes sem leader election.

## Topologia inicial planejada

```text
Load Balancer
      ↓
BEAM Node A   BEAM Node B   BEAM Node C
        \        |        /
             PostgreSQL
```

Todos os nodes usarão a mesma release inicialmente.

## Ainda não materializado

- cluster discovery;
- runtime release/deployment em múltiplos hosts;
- provider e infraestrutura como código;
- Postgres HA/backups;
- health/readiness completo;
- shutdown de release validado em cluster real;
- metrics/logging stack;
- object storage;
- retenção de RuntimeNode incarnations.

## Evolução condicionada por métricas

```text
homogeneous nodes
→ optional API/runtime specialization
→ package isolation
→ object storage
→ analytics store
→ external queue if proven necessary
```

Nenhuma especialização é pressuposta no V1.
