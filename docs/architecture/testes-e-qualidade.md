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
mix quality
```

O alias executa compilação com warnings como erros, verificação do formatter,
Credo strict, testes e Dialyzer para toda a umbrella. A configuração inicial
não possui suppressions do Dialyzer.

Enquanto `apps/` estiver vazio, o gate valida a PLT sem executar uma análise
sem BEAMs. A análise completa passa a ocorrer automaticamente após a criação da
primeira application.

`mix docs` entra no gate quando `ex_doc` for adicionada.

O workflow de CI permanece fora deste marco.

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
