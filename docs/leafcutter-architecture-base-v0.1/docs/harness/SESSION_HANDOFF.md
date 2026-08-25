# Handoff entre sessões

## Antes de encerrar

1. Atualize `docs/checkpoint/CURRENT.md`.
2. Registre ADR se a intenção arquitetural mudou.
3. Atualize docs in-code e externas impactadas.
4. Liste arquivos alterados.
5. Liste comandos/testes executados.
6. Registre risco ou ponto ainda aberto.
7. Defina uma próxima tarefa concreta e pequena.
8. Faça commit quando o estado estiver coerente.

## Conteúdo mínimo do checkpoint

```text
Current phase
Completed
In progress
Next concrete task
Relevant documents
Relevant code paths
Validation commands
Open risks
```

## Não fazer

- deixar a próxima sessão depender de uma conversa;
- escrever um resumo genérico sem arquivos concretos;
- marcar decisão como aprovada sem ADR/documentação;
- deixar docs divergirem do código conscientemente.
