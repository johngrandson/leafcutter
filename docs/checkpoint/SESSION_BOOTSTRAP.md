# Bootstrap para uma nova sessão

Use este processo apenas em ferramentas sem acesso ao repositório (ChatGPT web).

Codex CLI e Claude Code não precisam dele: ambos carregam `AGENTS.md` automaticamente (Claude Code via import em `CLAUDE.md`) e recebem `docs/checkpoint/CURRENT.md` pelo hook de `SessionStart` em `.codex/hooks.json` e `.claude/settings.json` (ADR-0015).

## Leitura

Siga a seção "Leitura obrigatória antes de trabalhar" de `AGENTS.md` (ordem canônica), colando o conteúdo dos arquivos na conversa quando a ferramenta não puder lê-los.

## Prompt de continuidade

```text
Estamos continuando o desenvolvimento do Leafcutter.

Leia primeiro AGENTS.md e docs/checkpoint/CURRENT.md. Depois leia os ADRs e documentos apontados pelo checkpoint. Inspecione o código atual antes de responder.

O desenvolvedor é o autor principal do código. Não implemente uma feature inteira sem pedido explícito. Atue primeiro como orientador e revisor. Mantenha mudanças pequenas, respeite ownership de contexts e destaque qualquer conflito entre código, documentação e ADRs.

Diga:
1. qual é a fase atual;
2. qual é a próxima tarefa concreta;
3. quais arquivos são relevantes;
4. quais decisões já estão aceitas;
5. qual ponto ainda exige ratificação.
```

## Ao encerrar uma sessão

Siga `docs/harness/SESSION_HANDOFF.md`.
