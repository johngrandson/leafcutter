# ADR-0015 — Harness multi-agente com contrato compartilhado

- Status: Accepted
- Estado de implementação: MATERIALIZADO

## Decisão

Codex, Claude Code e outros agentes seguem `AGENTS.md`, `CURRENT.md` e o operating model comum.

Hooks carregam contexto e executam formatação após edições conforme configuração versionada.

## Consequências

- agentes não inferem decisões ausentes;
- mudança arquitetural atualiza docs/ADR/checkpoint;
- code review verifica contratos e boundaries, não apenas compilação.
