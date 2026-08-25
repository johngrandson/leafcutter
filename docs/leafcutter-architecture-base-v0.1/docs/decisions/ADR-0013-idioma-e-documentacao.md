# ADR-0013 - Idioma e documentação

- Status: Accepted

## Decisão

Código e documentação dentro do código são 100% em inglês. Arquitetura e documentação externa são em pt-BR.

APIs públicas relevantes usam `@moduledoc`, `@doc`, `@typedoc`, `@spec` e erros nomeados/previsíveis.

## Consequências

- ExDoc funciona como documentação técnica viva;
- contratos de erro mais claros;
- docs precisam ser atualizadas junto da implementação;
- comentários explicam motivo, não repetem código.
