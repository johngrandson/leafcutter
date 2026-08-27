# ADR-0001 — Umbrella com poucas OTP applications

- Status: Accepted
- Estado de implementação: MATERIALIZADO

## Decisão

O Leafcutter usa uma umbrella com quatro boundaries operacionais:

```text
leafcutter_core
leafcutter_connectors
leafcutter_runtime
leafcutter_api
```

Contexts não recebem OTP application própria.

## Estado atual

As quatro apps existem e o grafo é:

```text
core       → none
connectors → none
runtime    → core + connectors
api        → core + runtime
```

## Consequências

- poucas supervision trees de topo;
- uma release inicial coesa;
- workflows podem compor contexts sem microservices;
- nova app exige boundary operacional real.

## Futuro preservado

Especialização de nodes ou releases separadas só entra após necessidade medida.
