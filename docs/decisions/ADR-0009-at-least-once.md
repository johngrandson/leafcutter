# ADR-0009 — Semântica at-least-once

- Status: Accepted
- Estado de implementação: PRINCÍPIO MATERIALIZADO; DATA PLANE PENDENTE

## Decisão

Se um efeito externo não pode ser provado, o trabalho pode ser repetido. O Leafcutter não promete exactly-once universal.

## Estado atual

Ownership, generation e recovery já assumem reconstrução/repetição segura de controle. O processamento externo ainda não existe.

## Consequências

Idempotency keys, upsert, SourceIdentity e IdentityMapping poderão reduzir duplicação quando o destino suportar.
