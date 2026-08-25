# CLAUDE.md

@AGENTS.md

## Claude Code

Adaptador do harness para o Claude Code (ADR-0015):

- `docs/checkpoint/CURRENT.md` é injetado automaticamente no início da sessão pelo hook `SessionStart` em `.claude/settings.json`.
- `mix format` roda automaticamente após `Edit`/`Write` em arquivos `.ex`/`.exs` (hook `PostToolUse`).
- Regras novas de agente entram em `AGENTS.md`, não aqui.
