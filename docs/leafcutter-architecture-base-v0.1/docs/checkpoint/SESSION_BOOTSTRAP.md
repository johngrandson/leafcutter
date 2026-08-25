# Bootstrap para uma nova sessão

Use este processo quando iniciar uma nova conversa com ChatGPT ou Codex.

## Leitura

1. Leia `AGENTS.md`.
2. Leia `docs/checkpoint/CURRENT.md`.
3. Leia `docs/decisions/README.md`.
4. Leia apenas os documentos listados como relevantes no checkpoint.
5. Inspecione o código, testes e migrations atuais.
6. Verifique o último diff ou commit relacionado ao marco corrente.

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

Atualize `CURRENT.md` com:

- decisão concluída;
- arquivos alterados;
- testes executados;
- riscos ou dúvidas;
- próxima tarefa concreta;
- documentos que a próxima sessão deve ler.
