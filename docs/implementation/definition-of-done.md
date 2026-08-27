# Definition of Done

Uma mudança relevante está concluída quando:

## Comportamento

- o contract público está explícito;
- invariantes vivem no context correto;
- erros têm forma previsível;
- concorrência/idempotência são tratadas quando relevantes;
- estado durável e operacional estão separados.

## Código

- `@moduledoc`, `@doc`, `@typedoc` e `@spec` seguem os padrões;
- typespecs não usam formas genéricas quando a shape é conhecida;
- não há abstração/processo/dependência sem necessidade concreta;
- boundaries de apps e contexts são preservadas.

## Verificação

- formatter passa;
- compile com warnings como errors passa;
- testes passam;
- Credo strict passa;
- Dialyzer passa;
- migrations dev/test foram aplicadas quando necessário.

## Documentação

- documentação diz o que existe de fato;
- futuro ratificado continua preservado;
- decisões abertas não são apresentadas como fechadas;
- ADR e specification são atualizados quando o contract muda;
- `CURRENT.md` avança quando há milestone.

## Review

- casos de falha e race conditions foram considerados;
- operação pode ser recuperada após crash conforme sua semântica;
- raw secrets não aparecem em local indevido;
- o slice não antecipa o próximo estágio.
