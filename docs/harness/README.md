# Harness de colaboração

O harness mantém continuidade entre desenvolvedor, Codex, Claude Code e outros agentes sem transformar conversa em fonte de verdade.

A base em `docs/knowledge/` guarda conhecimento derivado. `AGENTS.md`,
`CURRENT.md` e o operating model continuam sendo o contrato dos agentes.

## Arquivos

- `CODEX_OPERATING_MODEL.md`: modos de trabalho e limites.
- `TASK_BRIEF_TEMPLATE.md`: contract antes de implementação.
- `REVIEW_CHECKLIST.md`: review técnico/arquitetural.
- `CHANGE_PROTOCOL.md`: como alterar decisões e docs.
- `SESSION_HANDOFF.md`: passagem de contexto entre sessões.
- `QUALITY_ENFORCEMENT_ROADMAP.md`: trilha alternativa para fortalecer os gates
  de qualidade, sem alterar o roadmap do produto.
- `specifications/`: contratos dos incrementos alternativos antes da
  implementação.
- `plans/`: planos executáveis dos incrementos alternativos aprovados.

## Regra central

Toda tarefa deve separar:

```text
current materialized behavior
ratified future architecture
open decision
```

O agente não implementa futuro por inferência e não remove visão futura ao documentar um slice menor.
