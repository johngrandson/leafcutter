# Leafcutter - Checkpoint atual

> Atualize este arquivo ao terminar cada decisão, marco ou mudança de direção relevante.

## Current phase

**Architecture consolidation - Context Map and umbrella application boundaries**

## Repository state

- Projeto criado como umbrella vazia com `mix new leafcutter --umbrella`.
- Base de documentação arquitetural preparada.
- Nenhuma application de domínio deve ser criada antes da ratificação do Context Map e do grafo de apps.

## Accepted architecture baseline

- Umbrella com poucas OTP applications.
- Uma release inicial, preparada para separação futura.
- Phoenix Contexts maduros com facade raiz pequena, capability modules e implementação interna.
- Comunicação entre contexts: API pública síncrona, PubSub efêmero, persistência/Oban para obrigações duráveis.
- PostgreSQL como estado durável; OTP como estado operacional reconstruível.
- Um supervision subtree por Run.
- Broadway como data plane para source, enrichments opcionais e destinations.
- JSON Schema Draft 2020-12 como contrato canônico, validado inicialmente com JSV.
- Integration Packages versionados, declarados por `manifest.json` e inicialmente compilados com a mesma release.
- Connector -> Operation -> Transport.
- Transformation pura; Enrichment para side effects externos; Interceptor para transporte.
- Fan-out durável com `Record + N Deliveries` persistidos em batch e sem fila externa inicial.
- Semântica `at-least-once`.
- Ownership de Run por node com heartbeat por node, `owner_node` e `generation` como fencing token.
- API-first com OpenAPI canônico e Postman derivado.
- Código e docs in-code em inglês; arquitetura externa em pt-BR.
- Desenvolvedor como autor principal; Codex prioritariamente como guia/revisor.

## In progress

Ratificar, um por vez:

1. Phoenix Contexts definitivos.
2. Ownership de conceitos e tabelas.
3. APIs públicas e capability modules.
4. Apps da umbrella e grafo de dependências.

## Next concrete task

Revisar `docs/architecture/contextos-e-ownership.md` e aprovar, rejeitar ou alterar o primeiro context proposto: `Organizations`.

## Relevant documents

- `docs/architecture/contextos-e-ownership.md`
- `docs/architecture/umbrella-e-dependencias.md`
- `docs/architecture/principios-e-restricoes.md`
- `docs/decisions/ADR-0002-phoenix-contexts-maduros.md`

## Open warnings

- A divisão de contexts e apps contida nesta base está marcada como `PROPOSTA`.
- O mecanismo físico para compilar conteúdo de `packages/` junto da release ainda não foi ratificado.
- O JSON Schema definitivo de `manifest.json` ainda não foi fechado.
- Endpoints, tabelas, campos e índices concretos ainda não foram congelados.
