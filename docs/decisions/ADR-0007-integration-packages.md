# ADR-0007 — Integration Packages fora de `apps/`

- Status: Accepted
- Estado de implementação: ESTRUTURA RATIFICADA; MECANISMO DE BUILD ABERTO

## Decisão

```text
packages/<package>/
├── mix.exs
├── manifest.json
├── lib
└── test
```

Cada Package será Mix project independente, não uma quinta platform application.

## Estado atual

A estrutura e os contracts conceituais estão documentados, mas nenhum Package funcional ou mecanismo de inclusão na release foi materializado.

## Consequências

Build precisa ser explícito e auditável. Package não depende de internals de runtime/API.
