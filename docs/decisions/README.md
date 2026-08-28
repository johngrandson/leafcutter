# Architecture Decision Records

ADRs registram decisões duráveis. O status da decisão e o estado de implementação são dimensões diferentes.

```text
Accepted
→ a direção foi aprovada

Materialized / Partial / Not materialized
→ quanto dessa direção existe no código atual
```

| ADR | Decisão | Estado de implementação |
|---|---|---|
| ADR-0001 | Umbrella com poucas OTP applications | MATERIALIZADO |
| ADR-0002 | Phoenix Contexts maduros e APIs segmentadas | PARCIAL — Organizations e Executions foundation existem |
| ADR-0003 | Comunicação síncrona, PubSub e trabalho durável | PARCIAL |
| ADR-0004 | OTP operacional; PostgreSQL durável | MATERIALIZADO NO CONTROL PLANE |
| ADR-0005 | Broadway como data plane | NÃO MATERIALIZADO |
| ADR-0006 | JSON Schema 2020-12 + JSV | NÃO MATERIALIZADO |
| ADR-0007 | Integration Packages fora de `apps/` | ESTRUTURA RATIFICADA; BUILD ABERTO |
| ADR-0008 | Connector → Operation → Transport | NÃO MATERIALIZADO |
| ADR-0009 | Semântica `at-least-once` | MATERIALIZADA COMO PRINCÍPIO; DATA PLANE PENDENTE |
| ADR-0010 | Fan-out durável sem fila externa inicial | NÃO MATERIALIZADO |
| ADR-0011 | Ownership por RuntimeNode + generation/fencing | MATERIALIZADO, INCLUINDO RECOVERY |
| ADR-0012 | OpenAPI canônico; Postman derivado | PHOENIX FOUNDATION; OPENAPI PENDENTE |
| ADR-0013 | Idioma e documentação in-code | MATERIALIZADO |
| ADR-0014 | Desenvolvedor como autor principal e harness | MATERIALIZADO |
| ADR-0015 | Harness multi-agente com contrato compartilhado | MATERIALIZADO |
| ADR-0016 | Separação documental entre presente, futuro e aberto | MATERIALIZADO NESTA REVISÃO |
| ADR-0017 | RunSnapshot v1 imutável e criação atômica | MATERIALIZADO |

## Convenção de status decisório

- `Accepted`: decisão aprovada.
- `Proposed`: proposta aguardando ratificação.
- `Superseded`: substituída por ADR posterior.
- `Deprecated`: mantida somente como histórico.

## Regra de manutenção

Ao materializar uma decisão antes parcial ou futura, atualizar:

1. o ADR;
2. a documentação arquitetural relacionada;
3. specifications afetadas;
4. `checkpoint/CURRENT.md`.

Não reescrever um ADR para fingir que a decisão sempre teve a forma atual. Mudanças de direção devem ser registradas por novo ADR ou seção explícita de evolução.
