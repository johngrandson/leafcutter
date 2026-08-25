# Testes e qualidade

## Pirâmide prática

### Funções puras

- Transformation;
- identity building;
- payload hash;
- error classification;
- state transitions;
- configuration resolution;
- batching rules quando próprias.

Testes rápidos e determinísticos.

### Context tests

- API pública do context;
- constraints Ecto;
- ownership;
- transações;
- autorização;
- Run Snapshot.

### Connector/Operation tests

- request building;
- pagination;
- partial batch success;
- rate-limit metadata;
- error normalization;
- destination identity extraction.

Transport pode ser fakeado na borda.

### Runtime tests

- durable fan-out;
- claim concorrente;
- retry/available_at;
- checkpoint atomicity;
- crash/restart;
- stale generation rejection;
- destination isolation;
- graceful shutdown.

### Integration Package tests

- fixtures JSON;
- source Contract;
- Transformation;
- destination Contract;
- Enrichment preparation;
- Interceptors;
- manifest validation.

## In-code documentation

Módulos públicos relevantes possuem:

```text
@moduledoc
@doc
@typedoc
@spec
named error types
```

## Quality gates iniciais

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
```

Credo e Dialyzer são desejáveis, mas devem ser adicionados conscientemente e configurados para ajudar, não gerar ritual sem valor.

## Review

Toda revisão verifica:

- context ownership;
- SRP;
- ausência de abstração prematura;
- erro previsível;
- idempotency/replay;
- docs/specs;
- testes de falha;
- ausência de dados sensíveis.
