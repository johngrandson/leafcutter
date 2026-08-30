# Trilha alternativa de fortalecimento dos quality gates

> **Status: PLANEJAMENTO ALTERNATIVO.** Este documento organiza trabalho do
> harness. Ele não altera o checkpoint, a sequência dos slices de produto nem o
> estado de implementação dos ADRs.

## Objetivo

Tornar as regras obrigatórias do repositório verificáveis antes de cada commit.
O resultado esperado é um gate único, reproduzível por pessoas, agentes e CI,
que falhe quando o código não cumprir os contratos de qualidade materializados.

Esta trilha permanece separada da documentação do produto. Ela pode evoluir em
paralelo, mas só entra na fila de implementação quando o desenvolvedor escolher
um de seus incrementos. `docs/checkpoint/CURRENT.md` continua apontando apenas a
próxima fronteira do produto.

## Baseline em 2026-08-30

O alias raiz `mix quality` executa:

```text
knowledge linter unit tests
knowledge lint estrito
compile com warnings como erros
format check
Credo strict
testes da umbrella
Dialyzer
```

A auditoria desta trilha encontrou:

- `mix quality` verde em cerca de 18 segundos, com 61 testes do linter da base
  de conhecimento e 459 testes Elixir;
- nenhuma configuração `.credo.exs`, portanto o repositório usa somente os
  checks padrão do Credo;
- o check opt-in `Readability.Specs` encontra 12 funções públicas sem spec;
- `Readability.UnsafeToAtom` e `Design.SkipTestWithoutComment` passam quando
  habilitados isoladamente;
- os schemas Ecto atuais cumprem o formato canônico de `@doc` e possuem specs,
  mas nenhum gate protege esse contrato;
- `mix hex.audit`, `mix deps.unlock --check-unused` e o grafo xref
  `compile-connected` passam quando executados separadamente;
- o repositório não possui hook Git `pre-commit` funcional. O
  `core.hooksPath` global aponta para `.husky/`, que não existe no projeto;
- os hooks de Codex e Claude formatam depois de edições, mas são conveniências
  de sessão. Eles suprimem falhas do formatter e não validam um commit;
- não existe pipeline de CI versionado;
- `mix quality` ainda não protege o grafo esperado das OTP applications nem
  boundaries entre contexts;
- a base de conhecimento possui governança e lint determinístico, mas ainda
  não possui entradas ativas. O linter não verifica todos os invariantes de
  provenance e histórico.

## Decisões já alinhadas

- `mix quality` será a entrada canônica e compartilhada. Hooks, CI e adapters
  chamam esse gate em vez de reimplementar suas regras.
- As skills em `.claude/skills/` continuam adapters. Elas não se tornam fonte
  de enforcement e não substituem o Mix.
- Paridade de skills específicas para Codex fica fora do primeiro incremento e
  será avaliada separadamente.
- O futuro `pre-commit` executará o `mix quality` completo.
- O hook rejeitará arquivos tracked com mudanças unstaged. Assim, o estado
  validado não mistura o que entrará no commit com outra edição tracked.
- O hook apenas verifica. Ele não formata, corrige ou altera arquivos.

## Princípios da trilha

1. Cada regra automática precisa ter uma falha reproduzível que prove seu
   enforcement.
2. Checks novos entram em `mix quality` antes de serem chamados por hooks ou
   CI.
3. Regras automáticas devem medir contratos objetivos. Julgamento
   arquitetural continua no review checklist.
4. Checks opt-in do Credo entram individualmente. Não habilitar todo o conjunto
   desativado, pois algumas regras conflitam com decisões do Leafcutter.
5. Um checker de boundaries não pode proibir projeções públicas ratificadas.
   Ele deve rejeitar Repo, queries, changesets e internals de outro context.
6. Cada incremento precisa permanecer pequeno, testado e reversível.

## Roadmap

### H0. Consolidar o contrato de qualidade

Tornar `docs/implementation/quality-gates.md` a descrição detalhada do gate e
fazer os documentos do harness apontarem para ela. Remover listas duplicadas
que possam divergir. Registrar no ADR-0015 qualquer evolução normativa do
contrato compartilhado.

Saída:

- uma fonte documental para os comandos obrigatórios;
- separação explícita entre checks automáticos e review humano;
- política de validação do estado exato do commit.

### H1. Materializar `mix quality` v2

Adicionar enforcement em blocos independentes:

1. criar `.credo.exs`, corrigir as ausências reais de specs e habilitar somente
   `Readability.Specs`, `Readability.UnsafeToAtom` e
   `Design.SkipTestWithoutComment`;
2. incluir `mix hex.audit`, `mix deps.unlock --check-unused` e
   `mix xref graph --format cycles --label compile-connected --fail-above 0`;
3. adicionar checker nativo para o `@doc` canônico das funções públicas de
   schemas Ecto;
4. proteger o grafo exato das OTP applications;
5. proteger boundaries objetivas entre contexts, preservando projeções e
   tipos públicos ratificados.

Cada bloco começa com um teste negativo que falha pela violação pretendida.
Nenhuma dependency ou framework arquitetural novo faz parte deste incremento.

### H2. Validar o commit local exato

Versionar um hook Git e um instalador idempotente. O hook:

- confirma que o estado elegível para validação coincide com o commit;
- rejeita tracked files com alterações unstaged;
- executa o `mix quality` completo;
- propaga qualquer exit status sem mascarar falhas;
- nunca edita o working tree.

Um teste de integração cria um repositório temporário e prova sucesso, falha do
gate e rejeição de estado misto. A estratégia para arquivos untracked ainda
precisa ser fechada antes da especificação deste incremento.

### H3. Reproduzir o gate em CI limpa

Executar migrations desde zero, `mix quality` e compile de produção em um
ambiente limpo. Cache de dependencies e PLT pode reduzir tempo, mas não pode
ocultar uma execução fria quebrada. O arquivo concreto depende da escolha do
provedor de CI e não deve ser criado por inferência.

### H4. Fortalecer a integridade da base de conhecimento

Estender o linter de snapshot para verificar paths de provenance, valores de
contexto, estados, datas e rotas de shards. Adicionar checks de diff no
pre-commit para invariantes históricos:

- `raw/` aceita somente adições e não aceita symlinks;
- `log.md` é append-only;
- promoção preserva exatamente o corpo aprovado da proposta.

O linter continua read-only. A escrita na base mantém o ciclo de proposta e
aprovação do ADR-0020.

### H5. Formar conhecimento útil por uso real

Não fazer backfill amplo de ADRs na base derivada. Capturar somente correções
humanas, ambiguidades resolvidas, gotchas, sínteses e pins que surgirem no
trabalho. As skills atuais do Claude continuam aplicando esse fluxo como
adapters.

## Ordem e independência

```text
H0 contrato documental
→ H1 gate canônico
→ H2 pre-commit exato
→ H3 CI limpa

H4 integridade da knowledge base
→ usa H2 para checks históricos

H5 adoção
→ contínuo, orientado por ocorrências reais
```

H0 e H1 vêm primeiro porque hooks e CI devem consumir um gate já definido.
H4 pode evoluir em paralelo ao gate geral, mas seus checks de histórico só
entram depois do mecanismo de pre-commit.

## Decisões pendentes

- decidir se o pre-commit rejeita todos os arquivos untracked não ignorados ou
  valida o index em um checkout temporário;
- escolher o provedor de CI antes de materializar H3;
- definir o conjunto exato de referências cross-context permitidas antes do
  checker de boundaries de H1;
- definir quando esta trilha alternativa entra na fila em relação ao Slice
  26C2.

## Protocolo de execução

Cada incremento recebe sua própria specification e plano antes de código. A
implementação usa testes negativos primeiro, commits incrementais e o
`mix quality` vigente. A trilha só atualiza `CURRENT.md` se o desenvolvedor
decidir promovê-la a trabalho corrente do repositório.
