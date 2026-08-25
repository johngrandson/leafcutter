# Fatores IX a XII: operação e administração

> Pesquisa realizada em 25 de agosto de 2026. Material de aprendizagem e
> apoio ao planejamento. Não é um ADR, não ratifica decisões arquiteturais e
> não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

[Voltar ao índice](README.md)

## IX. Disposability

Processos descartáveis iniciam rápido, encerram de forma graciosa e toleram
morte súbita. Workers devem devolver trabalho ou permitir sua recuperação, e
jobs precisam ser reentrantes ou idempotentes
([fator IX](https://12factor.net/disposability)).

O Leafcutter já aceitou os mecanismos mais importantes para morte súbita:

- `at-least-once` em vez de uma promessa universal de exactly-once
  ([ADR-0009](../../decisions/ADR-0009-at-least-once.md));
- Records, Deliveries e checkpoint na mesma transação;
- leases/claims curtos, sem manter lock durante request externa;
- ownership recuperável e rejeição de generation antiga;
- supervisors para reconstruir processos.

Ainda há uma lacuna explícita: o processo concreto de graceful shutdown não foi
definido ([decisões em aberto](../../architecture/decisoes-em-aberto.md)). Também
faltam orçamento de startup, readiness durante boot, drain da API, interrupção
das pipelines, devolução de Deliveries em processamento e comportamento de Oban
durante shutdown.

Releases Mix propagam shutdown por SIGINT/SIGTERM e encerram applications e
supervision trees na ordem inversa de startup
([`mix release`, shutting down](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-shutting-down)).
Isso fornece o mecanismo, mas o Leafcutter ainda precisa definir como cada
pipeline conserva a invariável durável durante esse intervalo.

Testes mínimos futuros:

- SIGTERM durante request HTTP;
- SIGTERM durante fetch de source;
- SIGTERM antes e depois do commit de fan-out;
- SIGKILL durante side effect externo;
- restart com Delivery em `processing` e claim expirado;
- node antigo tentando escrever depois do takeover;
- deploy rolling sem perda de obrigação durável.

## X. Dev/prod parity

O fator pede pouca distância de tempo, pessoas e ferramentas entre
desenvolvimento e produção. Backing services devem manter tipo e versão tão
próximos quanto possível
([fator X](https://12factor.net/dev-prod-parity)).

O Leafcutter modela development, homologation e production como scopes de
cliente. Isso favorece promoção explícita e isolamento de Connections, mas não
prova paridade da plataforma
([ambientes, RBAC e homologação](../../architecture/ambientes-rbac-homologacao.md)).

Hoje não há:

- versão de Erlang/OTP, Elixir e Postgres fixada para todos os ambientes;
- forma declarativa de iniciar backing services locais;
- CI;
- build de release usado também em homologação;
- provider e target de produção;
- política de migrations compatível com deploy.

Paridade não significa colocar credenciais ou volumes de produção no notebook.
Significa usar o mesmo tipo de banco, os mesmos contratos, o mesmo caminho de
release e configurações com a mesma forma. Dados e secrets continuam distintos.
Ferramentas exclusivas de desenvolvimento, como Tidewave, podem permanecer fora
da release.

## XI. Logs

O manifesto trata logs como stream contínuo de eventos. A app escreve no stream
de saída, e a plataforma captura, roteia, indexa e retém esse conteúdo. O código
da app não gerencia arquivos de log
([fator XI](https://12factor.net/logs)).

O documento local de observabilidade separa corretamente três coisas:

- Execution Monitoring consulta Run, Records, Deliveries, Attempts e eventos
  duráveis;
- Platform Observability mede throughput, backlog, memória, DB e latência;
- AuditEvent registra ações humanas ou administrativas
  ([observabilidade e auditoria](../../architecture/observabilidade-e-auditoria.md)).

Nenhuma delas é sinônimo de log. Logs ajudam a diagnosticar o runtime, mas não
podem virar a autoridade de Delivery, AuditEvent ou checkpoint. PubSub também
não é um substituto porque é efêmero.

Faltam decisões e implementação para:

- saída de produção em `stdout`/`stderr`;
- formato e metadata estruturada;
- correlation IDs para request, organization, environment, run, record,
  delivery e attempt, com cuidado de cardinalidade;
- níveis e política de sampling;
- redaction antes da emissão;
- destino, retenção e acesso operados pela plataforma;
- integração entre logs, metrics e traces sem duplicar fatos duráveis.

A release Mix iniciada em foreground escreve logs na saída padrão por default e
deixa o process manager cuidar de captura e restart
([`mix release`, running the release](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-running-the-release)).
Isso é um bom default futuro, não uma política de observabilidade completa.

## XII. Admin processes

O fator pede que migrations, consoles e scripts one-off usem a mesma codebase,
release, config e isolamento de dependencies dos processos regulares
([fator XII](https://12factor.net/admin-processes)).

O Leafcutter ainda não tem migrations nem release tasks. O tooling Mix planejado
para validar, testar, buildar e publicar Integration Packages é principalmente
ferramenta de desenvolvimento. Ele não resolve por si só tarefas administrativas
contra um deploy.

O desenho futuro deve distinguir:

- migrations de schema;
- manutenção repetível e idempotente;
- backfills versionados e observáveis;
- inspeção remota excepcional;
- jobs duráveis de negócio ou manutenção em Oban;
- ações administrativas de domínio expostas pela API e AuditEvent.

Mix releases oferecem `eval` para uma VM one-off e `rpc` contra um node em
execução. A própria documentação sugere `eval` para preparos como migrations e
alerta que aplicações necessárias devem ser iniciadas explicitamente
([`mix release`, one-off commands](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-one-off-commands-eval-and-rpc)).
O projeto precisa escolher wrappers seguros e auditáveis quando Repo e release
existirem. Scripts locais soltos ou IEx manual não devem ser o processo normal
de produção.
