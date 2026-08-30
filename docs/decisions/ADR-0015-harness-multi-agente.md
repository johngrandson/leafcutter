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

## Evolução: gate compartilhado antes do commit

Em 2026-08-30, o contrato do harness passou a tratar `mix quality` como o gate
compartilhado entre pessoas e agentes. Checks focados podem antecipar feedback,
mas o autor executa o gate completo antes de cada commit.

`mix.exs` define o alias executável e
`docs/implementation/quality-gates.md` mantém sua descrição operacional. A
automação por pre-commit e CI permanece planejada na trilha alternativa de
quality enforcement. Este incremento documenta a obrigação manual e não
declara esses mecanismos como materializados.
