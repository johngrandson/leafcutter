# Princípios e restrições

> **Status: RATIFICADO.** Estas regras valem tanto para o código materializado quanto para a arquitetura futura.

## 1. Código e testes são a realidade executável

Documentação pode descrever o futuro, mas deve rotulá-lo. Quando um comportamento é apresentado como atual, ele precisa existir no código e nos testes.

## 2. Menor primitive correta

Ordem preferencial:

```text
Elixir/Erlang
→ OTP
→ Phoenix/Ecto/PubSub/Broadway/Oban
→ módulo/função simples
→ abstração própria somente com necessidade concreta
```

Não criar processo OTP sem estado ao longo do tempo, lifecycle, mensagens, coordenação, concorrência ou isolamento de falha.

## 3. PostgreSQL é autoridade durável

OTP representa estado operacional reconstruível. PostgreSQL explica ownership, progresso e de onde continuar após crash.

Materialização atual dessa regra:

```text
runtime_nodes.last_heartbeat_at
runs.owner_node_id
runs.generation
runs.ownership_acquired_at
```

## 4. Semântica at-least-once

O sistema não promete exactly-once universal. Se um efeito externo não pode ser provado, ele pode ser repetido. Idempotency, upsert e identity mapping reduzem duplicação quando o destino suporta.

## 5. Fencing em toda escrita crítica

Verificar ownership e escrever em comandos separados é incorreto. Toda mutação crítica futura deve incluir:

```text
run_id + runtime_node_id + generation
```

no mesmo comando SQL que altera estado.

## 6. Contexts são boundaries de domínio

Contexts não acessam schemas, queries ou internals de outros contexts. Referências por ID não criam dependência de API. Composição cross-context pertence a workflows na OTP application responsável pelo use case.

## 7. Poucas OTP applications

A divisão atual é:

```text
core
connectors
runtime
api
```

Não criar app por context nem microservice por antecipação.

## 8. Funções puras no centro

Transformation e regras determinísticas permanecem puras. HTTP, Repo, secrets, Telemetry e outros efeitos ficam nas bordas.

## 9. Broadway para o data plane futuro

Quando Record/Delivery processing for materializado, Broadway será a primitive para demand, bounded concurrency, batching e backpressure. Não duplicar manualmente essas capacidades.

## 10. Trabalho importante precisa de representação durável

PubSub e mensagens entre processos são efêmeros. Se trabalho não pode ser perdido, ele precisa de estado durável correspondente.

## 11. Uma release homogênea inicialmente

Todos os nodes executam a mesma release enquanto especialização de papéis não for justificada por métricas.

## 12. Segurança explícita

Raw secrets não entram em manifests, snapshots públicos, logs, eventos ou respostas. Payload access será permissionado separadamente de status e metadata.

## 13. Documentação preserva presente e futuro

Cada documento deve deixar claro:

```text
what exists
what is ratified next
what is still open
```

Omissão de status não transforma proposta em realidade.

## Restrições iniciais

Não adicionar sem caso comprovado:

- Kafka, RabbitMQ ou Redis;
- external queue por Delivery;
- Horde, `:global`, `:pg` ou lock distribuído como authority;
- repository pattern genérico;
- command/event bus genérico;
- macros arquiteturais ou DSL própria;
- múltiplos bancos por context;
- frontend como lugar de regra de negócio;
- SDKs antes da estabilização da API;
- isolamento de packages antes de existir necessidade operacional.
