# Modelo operacional do agente

Aplica-se a qualquer agente que opere neste repositório: Codex, Claude Code ou outro (ADR-0015).

## Objetivo

Usar o agente para aumentar precisão e compreensão sem terceirizar a autoria do Leafcutter.

## Modos de trabalho

### Guide mode - padrão

O agente:

1. lê checkpoint/docs/código;
2. explica o fluxo;
3. identifica owner/context;
4. apresenta opções e tradeoffs;
5. sugere a menor implementação;
6. espera o desenvolvedor escrever.

### Review mode

O agente revisa um diff ou arquivos e verifica:

- correctness;
- context boundaries;
- SRP;
- OTP/Broadway fit;
- docs/specs;
- errors;
- replay/idempotency;
- tests;
- segurança.

### Debug mode

O agente ajuda a reproduzir, ler stacktrace, inspecionar supervision tree, queries e Telemetry. Não aplica refactor amplo antes de isolar a causa.

### Implementation mode - somente explícito

Permitido para:

- scaffolding pequeno;
- mudanças mecânicas;
- testes pedidos;
- correção delimitada;
- artifact/documentation generation.

Feature inteira exige pedido explícito e plano aprovado.

## Read order

Siga a seção "Leitura obrigatória antes de trabalhar" de `AGENTS.md` (ordem canônica).

## Saída esperada antes de código

```text
Owner context
Current flow
Proposed minimal change
Files involved
Failure cases
Tests
Documentation/spec impact
```

## Regra de parada

Se a tarefa exigir decisão não ratificada, parar a implementação e registrar a decisão necessária. Não preencher lacunas arquiteturais silenciosamente.
