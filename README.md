# Leafcutter - Base de arquitetura e conhecimento

Este pacote consolida a arquitetura aprovada do Leafcutter e prepara o repositório para desenvolvimento manual, assistido por Codex e ChatGPT.

O Leafcutter é uma plataforma de integração orientada a código. Seu núcleo extrai dados de uma origem, valida contratos, aplica lógica Elixir, executa enriquecimentos opcionais e distribui os resultados de forma confiável para um ou mais destinos.

## Estado desta base

Esta versão diferencia explicitamente:

- **Decisões aceitas**: regras arquiteturais que já foram discutidas e aprovadas.
- **Propostas para ratificação**: organização final de contexts, apps da umbrella e campos concretos de persistência que ainda devem ser revisados um por vez.
- **Evoluções futuras**: capacidades planejadas, mas que não devem contaminar a implementação inicial.

Não trate uma seção marcada como `PROPOSTA` como decisão definitiva.

## Como instalar no repositório

Copie o conteúdo deste diretório para a raiz do projeto `leafcutter/` criado com:

```bash
mix new leafcutter --umbrella
```

A estrutura resultante deverá começar assim:

```text
leafcutter/
├── AGENTS.md
├── README.md
├── apps/
├── config/
├── docs/
├── mix.exs
└── packages/            # criado quando a especificação de packages for implementada
```

## Ordem de leitura

1. `docs/checkpoint/CURRENT.md`
2. `docs/architecture/como-o-leafcutter-foi-arquitetado.md`
3. `docs/architecture/principios-e-restricoes.md`
4. `docs/architecture/contextos-e-ownership.md`
5. `docs/architecture/umbrella-e-dependencias.md`
6. `docs/decisions/README.md`
7. `docs/harness/CODEX_OPERATING_MODEL.md`

## Regras de idioma

- Código, nomes de módulos/funções, testes, comentários e documentação dentro do código: **inglês**.
- Documentação arquitetural, decisões, roadmap e guias fora do código: **português brasileiro**.

## Fonte de verdade

A hierarquia de autoridade do projeto é:

```text
Código + testes
    ↓
ADRs e documentação arquitetural
    ↓
OpenAPI e JSON Schemas versionados
    ↓
CURRENT.md para o estado atual do trabalho
    ↓
Conversas e memória de agentes como apoio, nunca como autoridade final
```

## Princípio de autoria

O desenvolvedor é o autor principal do código. Agentes devem atuar prioritariamente como orientadores, revisores, pesquisadores e parceiros de diagnóstico. Mudanças amplas só devem ser implementadas por agente mediante pedido explícito.
