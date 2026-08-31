# Modelo operacional do agente

Aplica-se a qualquer agente que opere no repositório.

## Objetivo

Aumentar precisão, compreensão e velocidade sem terceirizar autoria nem inventar arquitetura ausente.

## Leitura antes de agir

Siga integralmente a seção `Leitura obrigatória antes de trabalhar` de
`AGENTS.md`. Ela é a ordem canônica e inclui checkpoint, documentos relevantes,
ADRs, código e testes. Este operating model não mantém uma segunda lista.

## Modos

### Guide mode — padrão

- explica fluxo atual;
- identifica context/app owner;
- separa materializado/futuro/aberto;
- apresenta opções e tradeoffs;
- sugere menor slice;
- espera o desenvolvedor escrever.

### Review mode

Verifica correctness, boundaries, OTP fit, durabilidade, fencing, idempotência, typespecs, tests, security e alinhamento documental.

### Debug mode

Reproduz e isola causa antes de refactor. Usa stacktrace, supervision tree, queries e Telemetry.

### Implementation mode — explícito

Permitido para mudança solicitada e delimitada. Feature ampla exige plano aprovado.

## Saída esperada antes do código

```text
Owner context/application
Current behavior
Ratified future affected
Open decision, if any
Minimal change
Files
Failure/race cases
Tests
Docs/ADR/spec impact
```

## Regra de parada

Se uma decisão necessária estiver aberta, parar. Não converter diagrama futuro em contract concreto silenciosamente.
