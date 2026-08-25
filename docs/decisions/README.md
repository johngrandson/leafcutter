# Architecture Decision Records

ADRs registram decisões arquiteturais duráveis. Atualize o ADR quando a decisão mudar; não apague o histórico.

| ADR | Status | Decisão |
|---|---|---|
| ADR-0001 | Accepted | Umbrella com poucas OTP applications |
| ADR-0002 | Accepted | Phoenix Contexts maduros e APIs segmentadas |
| ADR-0003 | Accepted | Comunicação síncrona, PubSub e trabalho durável |
| ADR-0004 | Accepted | OTP para estado operacional; Postgres para estado durável |
| ADR-0005 | Accepted | Broadway como data plane |
| ADR-0006 | Accepted | JSON Schema 2020-12 + JSV |
| ADR-0007 | Accepted | Integration Packages fora de `apps/` |
| ADR-0008 | Accepted | Connector -> Operation -> Transport |
| ADR-0009 | Accepted | Semântica `at-least-once` |
| ADR-0010 | Accepted | Fan-out durável sem fila externa inicial |
| ADR-0011 | Accepted | Ownership por node + generation/fencing |
| ADR-0012 | Accepted | OpenAPI canônico; Postman derivado |
| ADR-0013 | Accepted | Idioma e documentação in-code |
| ADR-0014 | Accepted | Desenvolvedor como autor principal e harness versionado |
| ADR-0015 | Accepted | Harness multi-agente com contrato compartilhado |

## Convenção

- `Accepted`: decisão aprovada.
- `Proposed`: proposta ainda não ratificada.
- `Superseded`: substituída por ADR posterior.
- `Deprecated`: mantida somente por histórico.
