# Leafcutter - Base de arquitetura e conhecimento

O Leafcutter é uma plataforma de integração orientada a código. Seu núcleo extrai dados de uma origem, valida contratos, aplica lógica Elixir, executa enriquecimentos opcionais e distribui os resultados de forma confiável para um ou mais destinos.

Este repositório concentra tanto a implementação quanto a arquitetura, decisões e regras que orientam a evolução do produto.

## Estado atual

A foundation arquitetural e operacional está materializada em quatro OTP applications. O
workflow transacional `EnvironmentDeployment → RunSnapshot v1`, ContractVersion
executável, Operations Read/Write, Transport HTTP bounded e Package Manifest/resolução
compilada estão concluídos até o Slice 26C2.

A próxima fronteira de produto é o Slice 26C3. Ele ainda precisa de ratificação para
selecionar um fluxo externo real completo: exatamente uma Operation Read de origem e uma
ou mais Operations Write de destino. A escolha de sistemas, endpoints e semânticas
vendor-specific permanece aberta; a inventory de packages de produção continua vazia.

A trilha alternativa de qualidade materializou H0 e H1A. Os incrementos seguintes do
harness permanecem separados da sequência de produto.

Esta base diferencia explicitamente:

- **Decisões aceitas**: regras arquiteturais discutidas e aprovadas.
- **Propostas para ratificação**: decisões que não podem orientar implementação antes de aprovação.
- **Evoluções futuras**: capacidades planejadas que não descrevem o código atual.

Não trate uma seção marcada como `PROPOSTA` como decisão definitiva. O estado
exato e a próxima tarefa ficam em `docs/checkpoint/CURRENT.md`.

## Estrutura do repositório

```text
leafcutter/
├── AGENTS.md
├── apps/
├── config/
├── docs/
├── packages/
├── mix.exs
└── README.md
```

Responsabilidades principais:

- `apps/`: OTP applications da umbrella.
- `config/`: configuração compartilhada da umbrella.
- `docs/`: arquitetura, ADRs, harness, checkpoints, especificações e guias de implementação.
- `packages/`: Integration Packages separados da plataforma, selecionados por inventory explícita.
- `AGENTS.md`: regras operacionais para agentes trabalhando no repositório.

As quatro applications e seu grafo de dependências estão materializados. Novas divisões só
podem surgir após ratificação explícita.

## Ordem de leitura

Antes de trabalhar no projeto, consulte nesta ordem:

1. `docs/checkpoint/CURRENT.md`
2. os documentos listados em `Relevant documents` no checkpoint
3. `docs/decisions/README.md`
4. documentação arquitetural relacionada à tarefa
5. código e testes existentes

Para uma leitura geral da arquitetura:

1. `docs/architecture/como-o-leafcutter-foi-arquitetado.md`
2. `docs/architecture/principios-e-restricoes.md`
3. `docs/architecture/visao-geral.md`
4. `docs/architecture/modelo-conceitual.md`
5. `docs/architecture/contextos-e-ownership.md`
6. `docs/architecture/umbrella-e-dependencias.md`

O índice completo da documentação está disponível em `docs/README.md`.

## Regras de idioma

Código e documentação dentro do código devem ser escritos em inglês, incluindo:

- nomes de módulos e funções;
- `@moduledoc`;
- `@doc`;
- `@typedoc`;
- `@spec`;
- comentários;
- testes;
- fixtures;
- contratos de erro;
- exemplos de código.

Documentação arquitetural, decisões, roadmap, checkpoints e guias externos ao código permanecem em português brasileiro.

## Fontes de verdade

A autoridade depende do tipo de informação.

| Assunto                         | Fonte canônica                   |
| ------------------------------- | -------------------------------- |
| Comportamento implementado      | Código + testes                  |
| Intenção arquitetural           | ADRs e documentação arquitetural |
| Contrato HTTP da plataforma     | OpenAPI                          |
| Contratos de payload            | JSON Schema versionado           |
| Estado atual do desenvolvimento | `docs/checkpoint/CURRENT.md`     |
| Regras para agentes             | `AGENTS.md`                      |

Quando duas fontes divergirem, a divergência deve ser tratada explicitamente.

Código que não corresponde ao OpenAPI, por exemplo, representa uma inconsistência que precisa ser resolvida. A existência da implementação não significa automaticamente que o contrato deixou de ser válido.

Da mesma forma, uma mudança arquitetural relevante na implementação deve atualizar o ADR ou documento que registra sua intenção.

Conversas com ChatGPT, Codex ou outros agentes podem fornecer contexto, mas não são fonte canônica do projeto.

## Princípio de autoria

O desenvolvedor é o autor principal do código.

Agentes devem atuar prioritariamente como:

- orientadores técnicos;
- revisores;
- pesquisadores;
- parceiros de debugging;
- executores de verificações;
- autores de mudanças pequenas e explicitamente solicitadas.

Features inteiras, refactors amplos ou novas abstrações não devem ser implementados por agentes sem solicitação explícita.

## Ferramentas de desenvolvimento

### Tidewave

O Tidewave é executado no nível raiz da umbrella para permitir a inspeção das applications carregadas no runtime de desenvolvimento.

Execute:

```bash
mix tidewave
```

Por padrão, o endpoint MCP fica disponível em:

```text
http://localhost:4001/tidewave/mcp
```

A porta pode ser alterada por meio da variável de ambiente `TIDEWAVE_PORT`.

Tidewave e Bandit são dependências exclusivas de desenvolvimento e não fazem parte da release de produção.

## Estado de implementação

A umbrella materializa:

~~~text
leafcutter_core       → PostgreSQL, contexts duráveis, PubSub e Oban
leafcutter_connectors → contracts de Operation, Package e Transport HTTP
leafcutter_runtime    → resolução compilada, ownership e recovery de Runs
leafcutter_api        → boundary Phoenix e raiz da release
~~~

Os Slices 26A, 26B, 26C1 e 26C2 estão concluídos. `RunSnapshot v1` permanece
inalterado, e nenhum package de produto entra na release antes da ratificação de 26C3.

Consulte `docs/checkpoint/CURRENT.md` para o inventário completo do estado
materializado e `docs/implementation/quality-gates.md` para a validação local.
