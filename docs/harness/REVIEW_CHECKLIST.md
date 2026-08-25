# Checklist de revisão

## Boundaries

- O owner context está correto?
- A mudança acessa internals de outro context?
- A facade raiz cresceu indevidamente?
- Capability module seria mais coerente?

## Simplicidade

- Existe uma função simples no lugar de nova abstração?
- O processo OTP possui estado/lifecycle/failure boundary real?
- Há camada que apenas delega?
- Dependency nova elimina código suficiente?

## Runtime

- Estado durável está no Postgres?
- Estado operacional é reconstruível?
- Semântica `at-least-once` foi considerada?
- Partial batch success está preservado?
- `generation` protege escrita crítica?

## Contracts

- Source/destination JSON Schema correto?
- Erro normalizado e previsível?
- `@spec` corresponde à implementação?
- Dados sensíveis foram redigidos?

## Tests

- Happy path?
- Invalid data?
- Retryable/permanent error?
- Crash/recovery quando aplicável?
- Concorrência/claim quando aplicável?

## Documentation

- Código e docs in-code em inglês?
- `@moduledoc`, `@doc`, `@typedoc`, `@spec`?
- Docs/ADR/checkpoint atualizados?
