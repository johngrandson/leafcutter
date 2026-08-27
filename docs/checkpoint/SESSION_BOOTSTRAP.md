# Bootstrap para uma nova sessão

Codex CLI e Claude Code carregam `AGENTS.md` e `CURRENT.md` por configuração/hook. Use este processo manual somente quando a ferramenta não puder ler o repositório.

## Leitura canônica

1. `AGENTS.md`.
2. `docs/checkpoint/CURRENT.md`.
3. `docs/architecture/estado-atual-e-visao-futura.md`.
4. `docs/decisions/README.md` e ADRs relevantes.
5. Código e testes da área atual.
6. Specification relacionada, quando existir.

## Perguntas obrigatórias antes de agir

```text
What exists in code now?
What is ratified but not implemented?
What is still open?
Which context/application owns the change?
Which tests prove the current behavior?
```

## Prompt de continuidade

```text
Estamos continuando o desenvolvimento do Leafcutter.

Leia AGENTS.md, docs/checkpoint/CURRENT.md e docs/architecture/estado-atual-e-visao-futura.md. Depois leia os ADRs, código e testes relevantes.

Separe explicitamente:
1. estado materializado;
2. arquitetura ratificada ainda futura;
3. decisões abertas.

O desenvolvedor é o autor principal. Não implemente feature ampla sem pedido explícito. Respeite boundaries, use typespecs precisos, preserve a visão futura válida e destaque qualquer divergência entre código, testes e documentação.

Informe a fase atual, próxima tarefa concreta, arquivos relevantes e ponto que ainda exige ratificação.
```

## Encerramento

Atualize `CURRENT.md` somente quando houver marco ou mudança de direção e siga `docs/harness/SESSION_HANDOFF.md`.
