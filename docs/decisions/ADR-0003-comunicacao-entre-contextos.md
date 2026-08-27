# ADR-0003 — Comunicação entre contexts

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO

## Decisão

Chamadas síncronas passam por APIs públicas. PubSub propaga fatos efêmeros. Trabalho que não pode ser perdido precisa de representação durável.

## Estado atual

Contexts materializados expõem APIs públicas. `Leafcutter.PubSub` e Oban são compartilhados. Ownership/recovery de Run possuem estado durável próprio.

O mecanismo físico para fatos duráveis cross-context obrigatórios ainda não foi materializado.

## Consequências

- nenhum event bus genérico;
- PubSub não substitui outbox/durable work;
- consumers de fatos duráveis recebem envelope self-contained;
- workflows coordenam use cases cross-context.
