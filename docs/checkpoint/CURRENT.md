# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante. Estrutura: `docs/templates/CHECKPOINT_TEMPLATE.md`.

## Current phase

**Architecture consolidation - Context Map and umbrella application boundaries**

## Completed

- Umbrella criada com `mix new leafcutter --umbrella`; nenhuma application de domínio existe ainda.
- Base de documentação arquitetural preparada.
- Baseline arquitetural ratificado em ADR-0001 a ADR-0014; consulte `docs/decisions/README.md` e `docs/architecture/principios-e-restricoes.md` em vez de resumos duplicados.
- Harness multi-agente instalado (ADR-0015): `CLAUDE.md`, `.claude/settings.json`, `.codex/hooks.json`.
- `mix tidewave` disponível na raiz da umbrella para inspeção do runtime de desenvolvimento.

## In progress

Ratificar, um por vez:

1. Phoenix Contexts definitivos.
2. Ownership de conceitos e tabelas.
3. APIs públicas e capability modules.
4. Apps da umbrella e grafo de dependências.

Nenhuma application de domínio deve ser criada antes da ratificação do Context Map e do grafo de apps.

## Next concrete task

Revisar `docs/architecture/contextos-e-ownership.md` e aprovar, rejeitar ou alterar o primeiro context proposto: `Organizations`.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Relevant code paths

- `mix.exs` (raiz da umbrella, alias `tidewave`)
- `apps/` (vazio até a ratificação do Context Map)

## Validation commands

```bash
mix format --check-formatted
mix compile --warnings-as-errors
```

## Open risks

- A divisão de contexts e apps contida nesta base está marcada como `PROPOSTA`.
- O mecanismo físico para compilar conteúdo de `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo de `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
