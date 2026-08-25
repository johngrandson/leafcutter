# ADR-0007 - Integration Packages

- Status: Accepted

## Decisão

Código específico de integrações vive em `packages/`, separado de `apps/`. Cada Package possui `manifest.json`, schemas, módulos Elixir e testes. Inicialmente participa do mesmo build/release.

Package é versionado e imutável; Integration é configuração de cliente; Run é execução.

## Consequências

- core da plataforma não conhece clientes;
- Git/testes/versionamento normais;
- estratégia física de compilação ainda precisa ser ratificada;
- caminho aberto para artifacts isolados no futuro.
