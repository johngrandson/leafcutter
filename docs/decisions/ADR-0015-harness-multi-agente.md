# ADR-0015 - Harness multi-agente com contrato compartilhado

- Status: Accepted

## Contexto

O harness foi escrito originalmente pelo Codex para sessões do Codex e do ChatGPT. O repositório passou a ser operado também pelo Claude Code, que não lê `AGENTS.md` nativamente e operava fora das regras do harness. Além disso, a fonte de verdade estava restated em vários documentos, com quatro ordens de leitura divergentes.

## Decisão

`AGENTS.md` é o contrato canônico para todos os agentes. Cada ferramenta tem um adaptador fino e versionado:

- Codex lê `AGENTS.md` nativamente; hooks em `.codex/hooks.json`.
- Claude Code lê `AGENTS.md` via import em `CLAUDE.md`; hooks em `.claude/settings.json`.
- ChatGPT web usa o prompt de `docs/checkpoint/SESSION_BOOTSTRAP.md`.

Os hooks espelham o mesmo comportamento nos dois lados: injetar `docs/checkpoint/CURRENT.md` no início da sessão e rodar `mix format` após edições.

A ordem de leitura canônica é a seção "Leitura obrigatória antes de trabalhar" de `AGENTS.md`; os demais documentos apenas a referenciam. O modelo operacional (`docs/harness/CODEX_OPERATING_MODEL.md`) vale para todos os agentes.

## Consequências

- nenhum agente opera fora do harness;
- regras novas de agente entram em `AGENTS.md`; adaptadores carregam apenas mecânica específica da ferramenta;
- `.gitignore` versiona `.claude/settings.json` e `.codex/hooks.json`, mantendo diretórios de trabalho locais fora do git;
- cada fato do harness tem um único lugar canônico; o checkpoint aponta para o índice de ADRs em vez de restater o baseline;
- ADR-0014 permanece válido: o desenvolvedor é o autor principal.
