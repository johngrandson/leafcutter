# Twelve-Factor App no Leafcutter

> Pesquisa realizada em 25 de agosto de 2026. Este conjunto documental é
> material de aprendizagem e apoio ao planejamento. Não é um ADR, não ratifica
> decisões arquiteturais e não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

## Ordem de leitura

1. [Fundamentos, limites e vocabulário](01-fundamentos-e-vocabulario.md)
2. [Fatores I a IV: codebase, dependencies, config e backing services](02-fatores-codebase-a-backing-services.md)
3. [Fatores V a VIII: build, processes, port binding e concurrency](03-fatores-build-a-concurrency.md)
4. [Fatores IX a XII: disposability, parity, logs e admin processes](04-fatores-disposability-a-admin-processes.md)
5. [Roadmap do Leafcutter](05-roadmap-leafcutter.md)
6. [Backlog e checklist para agentes](06-checklist-para-agentes.md)

## Resumo executivo

The Twelve-Factor App é uma metodologia para construir software entregue como
serviço. Seu tema central é o contrato entre uma aplicação e a plataforma que a
executa. A metodologia procura tornar setup, deploy, operação, substituição de
recursos e escala previsíveis sem amarrar o código a uma infraestrutura
específica. O texto oficial também declara que os fatores independem de
linguagem e da combinação de banco, fila, cache e outros serviços usados pela
aplicação ([introdução oficial](https://12factor.net/)).

O texto publicado em `12factor.net` foi escrito por Adam Wiggins e informa a
última atualização em 2017. A iniciativa oficial abriu o manifesto à comunidade
em 2024 porque seus princípios continuam úteis, mas vários exemplos e
recomendações envelheceram. A futura versão está sendo preparada no branch
`next` e ainda substituirá o site atual somente quando os mantenedores
concluírem a rodada de mudanças
([repositório oficial](https://github.com/twelve-factor/twelve-factor),
[anúncio da atualização](https://12factor.net/blog/open-source-announcement)).
Logo, este estudo usa o site publicado como doutrina original e trata o material
do branch `next` como contexto de evolução, não como norma concluída.

O Leafcutter tem uma direção compatível com os objetivos de concorrência e
descartabilidade. PostgreSQL como autoridade durável, estado OTP reconstruível,
fan-out persistido, semântica `at-least-once` e recovery com fencing são decisões
úteis para uma aplicação que precisa sobreviver a crashes. O fator de processos
exige uma leitura adaptada, porque Runs longos mantêm estado operacional dentro
da BEAM mesmo quando a verdade durável permite reconstruí-los. Toda essa
compatibilidade ainda é arquitetural. A umbrella está vazia e nenhum runtime de
domínio existe, conforme o
[checkpoint atual](../../checkpoint/CURRENT.md).

As maiores lacunas estão na fronteira entre código e operação: configuração de
deploy, identidade e imutabilidade da release, CI, port binding, logs, tarefas
administrativas, paridade entre ambientes e graceful shutdown. Parte dessas
lacunas é deliberada, porque provider e topologia de deploy ainda não foram
escolhidos. Não seria correto resolvê-las agora com Docker, Kubernetes ou uma
nova abstração. Primeiro o projeto precisa terminar o Context Map e ratificar o
grafo das OTP applications.

## Como interpretar esta avaliação

Os termos abaixo evitam que uma intenção escrita seja confundida com
comportamento entregue.

| Classificação | Significado |
|---|---|
| Evidenciado | Há código, configuração ou teste observável no repositório. |
| Direção ratificada | Um ADR ou baseline aceito estabelece a intenção, mas a implementação ainda pode faltar. |
| Proposto | O documento local marca a decisão como proposta ou deixa pontos de ratificação. |
| Lacuna | A documentação ou implementação necessária ainda não existe. |
| Prematuro | Só poderá ser decidido ou verificado depois de um marco anterior. |

Não existe neste relatório uma nota de "conformidade Twelve-Factor". O método
não é uma certificação, e o estado atual do Leafcutter não permite testar a maior
parte dos fatores em produção. A pergunta útil é outra: qual risco cada fator
revela e em qual etapa esse risco deve ser tratado?

## Visão geral dos doze fatores no Leafcutter

| Fator | Estado atual | Leitura curta |
|---|---|---|
| I. Codebase | Parcialmente evidenciado | Um repositório Git e uma release homogênea proposta; ainda não há deploys. |
| II. Dependencies | Parcialmente evidenciado | `mix.exs` e `mix.lock` existem; toolchain, packages e dependências de sistema ainda não estão fechados. |
| III. Config | Lacuna deliberada | Não há contrato de runtime config nem secret provider; configuração de domínio já está conceitualmente separada. |
| IV. Backing services | Direção ratificada | PostgreSQL é autoridade durável e Connections resolve recursos externos; nada foi implementado. |
| V. Build, release, run | Lacuna e decisão pendente | Release homogênea é proposta, mas build de packages, CI, artifact ID, migrations e deploy não estão definidos. |
| VI. Processes | Direção ratificada | Estado durável no Postgres e estado operacional reconstruível em OTP; faltam provas por crash tests. |
| VII. Port binding | Prematuro | `leafcutter_api` e o Phoenix Endpoint ainda são propostas. Tidewave de desenvolvimento não conta. |
| VIII. Concurrency | Direção ratificada | Broadway, nodes homogêneos e ownership por node formam uma boa direção; runtime não existe. |
| IX. Disposability | Direção forte com lacuna | Recovery e replay foram aceitos; startup, shutdown e drain continuam abertos. |
| X. Dev/prod parity | Lacuna | Os ambientes de domínio estão modelados, mas não há contrato de paridade de toolchain e backing services. |
| XI. Logs | Lacuna | A distinção entre monitoring, eventos e observabilidade existe; o stream de logs de produção não foi definido. |
| XII. Admin processes | Lacuna | Mix tooling futuro não equivale a tarefas administrativas da release; migrations e one-offs não foram desenhados. |

## Fontes primárias

### Twelve-Factor oficial

- [Introdução e índice dos fatores](https://12factor.net/)
- [I. Codebase](https://12factor.net/codebase)
- [II. Dependencies](https://12factor.net/dependencies)
- [III. Config](https://12factor.net/config)
- [IV. Backing services](https://12factor.net/backing-services)
- [V. Build, release, run](https://12factor.net/build-release-run)
- [VI. Processes](https://12factor.net/processes)
- [VII. Port binding](https://12factor.net/port-binding)
- [VIII. Concurrency](https://12factor.net/concurrency)
- [IX. Disposability](https://12factor.net/disposability)
- [X. Dev/prod parity](https://12factor.net/dev-prod-parity)
- [XI. Logs](https://12factor.net/logs)
- [XII. Admin processes](https://12factor.net/admin-processes)
- [Repositório oficial da revisão](https://github.com/twelve-factor/twelve-factor)
- [Visão da revisão, branch `next`](https://github.com/twelve-factor/twelve-factor/blob/next/VISION.md)
- [FAQ da revisão, branch `next`](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)
- [Anúncio oficial da abertura e modernização](https://12factor.net/blog/open-source-announcement)

### Elixir e Mix oficiais

- [`mix release`](https://hexdocs.pm/mix/Mix.Tasks.Release.html)

### Fontes canônicas do Leafcutter

- [Checkpoint atual](../../checkpoint/CURRENT.md)
- [Índice de ADRs](../../decisions/README.md)
- [Contextos e ownership](../../architecture/contextos-e-ownership.md)
- [Umbrella e dependências](../../architecture/umbrella-e-dependencias.md)
- [Runtime OTP e Broadway](../../architecture/runtime-otp-broadway.md)
- [Durabilidade e recovery](../../architecture/durabilidade-e-recovery.md)
- [Cluster e infraestrutura](../../architecture/cluster-e-infraestrutura.md)
- [Observabilidade e auditoria](../../architecture/observabilidade-e-auditoria.md)
- [Decisões em aberto](../../architecture/decisoes-em-aberto.md)
- [Roadmap arquitetural](../../architecture/roadmap.md)
- [Sequência de implementação](../../implementation/sequence.md)
- [Quality gates](../../implementation/quality-gates.md)
