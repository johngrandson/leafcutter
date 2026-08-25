# ADR-0009 - Semântica at-least-once

- Status: Accepted

## Decisão

Se não é possível provar que um efeito externo terminou, o trabalho pode ser repetido. O Leafcutter não promete exactly-once universal.

Idempotency, upsert, Source Identity e IdentityMapping são usados para replay seguro quando disponíveis.

## Consequências

- recovery simples e honesto;
- duplicatas são uma possibilidade de domínio;
- Operations e Packages devem considerar idempotency;
- checkpoint pode ficar atrás do estado operacional.
