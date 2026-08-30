# H0: contrato documental dos quality gates

> **Status: MATERIALIZADO NA TRILHA ALTERNATIVA.** Este contrato não altera a
> próxima tarefa de produto em `CURRENT.md`.

Roadmap:
`docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md`.

## Objetivo

Consolidar a descrição dos quality gates e exigir o gate completo antes de cada
commit. H0 muda somente documentação. O alias, os checks e o comportamento do
repositório continuam iguais até os incrementos posteriores.

## Autoridades documentais

Cada arquivo possui uma responsabilidade:

| Arquivo | Responsabilidade |
|---|---|
| `mix.exs` | definição executável do alias `mix quality` |
| `AGENTS.md` | regras obrigatórias e ordem de leitura dos agentes |
| `docs/implementation/quality-gates.md` | descrição detalhada dos comandos e de quando executá-los |
| `docs/architecture/testes-e-qualidade.md` | estratégia de testes, sem copiar a composição do alias |
| `docs/harness/*.md` | protocolo de trabalho, com links para as fontes acima |
| `docs/decisions/ADR-0015-harness-multi-agente.md` | decisão durável sobre o contrato compartilhado |

Se a lista documental de comandos divergir de `mix.exs`, `mix.exs` descreve o
comportamento materializado e a documentação precisa ser corrigida.

## Contrato antes do commit

Durante o desenvolvimento, checks focados continuam permitidos para feedback
rápido. Eles não substituem o gate final.

Antes de cada commit, o autor executa:

```bash
mix quality
```

H0 documenta uma obrigação manual. Ele não cria hook Git. H2 materializará a
verificação automática do estado exato do commit.

Mudanças com migration continuam exigindo, antes do gate:

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
mix quality
```

## Checks automáticos e review humano

`docs/implementation/quality-gates.md` lista somente comandos materializados no
alias atual e os comandos adicionais para migrations. Ele separa esses checks
das verificações que ainda dependem de julgamento humano.

O gate automático não prova sozinho:

- conformidade com decisões ratificadas;
- ownership e uso correto de APIs públicas entre contexts;
- necessidade de um processo OTP ou de uma nova abstração;
- impacto em ADRs, specifications e contracts externos;
- ausência de dados sensíveis em shapes ainda não cobertas por checks.

Esses itens permanecem no review checklist. H0 não os descreve como
enforcement automático.

## Eliminação de cópias

`docs/architecture/testes-e-qualidade.md` mantém a estratégia e a cobertura de
testes. A seção do gate aponta para
`docs/implementation/quality-gates.md` e não repete a lista interna do alias.

`docs/harness/CODEX_OPERATING_MODEL.md` aponta para a ordem de leitura em
`AGENTS.md`. Ele não mantém uma segunda sequência que possa divergir.

`CHANGE_PROTOCOL.md`, `REVIEW_CHECKLIST.md` e `TASK_BRIEF_TEMPLATE.md` usam
`mix quality` e apontam para a descrição canônica. Eles não copiam os comandos
internos do alias.

## Evolução do ADR-0015

A materialização de H0 adiciona uma seção de evolução ao ADR-0015. Ela
registra:

- `mix quality` como gate compartilhado entre pessoas e agentes;
- execução obrigatória antes de cada commit;
- checks focados como feedback intermediário, não substituto;
- automação de pre-commit e CI ainda não materializada.

O estado geral do ADR continua materializado para o contrato atual. O texto
não afirma que H2 ou H3 existem.

## Evidência materializada

- `docs/implementation/quality-gates.md`;
- `docs/decisions/ADR-0015-harness-multi-agente.md`;
- `docs/architecture/testes-e-qualidade.md`;
- `docs/harness/CODEX_OPERATING_MODEL.md`;
- `docs/harness/CHANGE_PROTOCOL.md`;
- `docs/harness/REVIEW_CHECKLIST.md`;
- `docs/harness/TASK_BRIEF_TEMPLATE.md`.

## Fora de escopo

- alterar `mix.exs` ou qualquer check do alias;
- criar `.credo.exs`;
- corrigir specs de código;
- criar hook, instalador ou CI;
- implementar checker de docs, grafo de applications ou boundaries;
- alterar a base de conhecimento;
- atualizar `CURRENT.md`;
- alterar ADRs ou specifications de produto.

## Critérios de aceitação

- `docs/implementation/quality-gates.md` declara `mix quality` antes de cada
  commit e continua fiel ao alias atual;
- `docs/architecture/testes-e-qualidade.md` não copia a lista interna do alias;
- `docs/harness/CODEX_OPERATING_MODEL.md` referencia a ordem canônica de
  `AGENTS.md`;
- os documentos operacionais do harness apontam para
  `docs/implementation/quality-gates.md`;
- o ADR-0015 registra a evolução sem declarar hook ou CI materializados;
- nenhum arquivo de produto, código, teste ou checkpoint muda;
- `git diff --check` e `mix quality` passam.
