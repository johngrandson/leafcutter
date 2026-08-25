# ADR-0002 - Phoenix Contexts maduros e APIs segmentadas

- Status: Accepted

## Contexto

Uma facade única por context pode se tornar god module. DDD/hexagonal rígido adicionaria cerimônia excessiva.

## Decisão

Usar Phoenix Contexts como arquitetura principal, com:

```text
root facade pequena
capability modules públicos
internal modules
ownership de schemas/queries
```

Outros contexts usam apenas APIs públicas. O root module não reexporta toda a API.

## Consequências

- navegação simples;
- SRP sem explosão de camadas;
- exige disciplina de ownership e testes de boundaries.
