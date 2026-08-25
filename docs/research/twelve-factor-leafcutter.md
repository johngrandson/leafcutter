# Twelve-Factor App: guia, avaliação do Leafcutter e roadmap

> Pesquisa realizada em 25 de agosto de 2026. Este documento é material de
> aprendizagem e apoio ao planejamento. Ele não é um ADR, não ratifica decisões
> arquiteturais e não substitui `docs/checkpoint/CURRENT.md`.

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
[checkpoint atual](../checkpoint/CURRENT.md).

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

## O que o Twelve-Factor é, e o que não é

### O problema que a metodologia tenta resolver

O manifesto nasceu da experiência de construir e operar aplicações SaaS. Seus
objetivos declarados incluem setup automatizável, contrato claro com o sistema
operacional, portabilidade, pouca divergência entre desenvolvimento e produção
e escala sem troca substancial das práticas de desenvolvimento
([introdução oficial](https://12factor.net/)).

Isso delimita seu alcance. O Twelve-Factor fala principalmente da interface
entre código e plataforma. A própria FAQ da atualização diz que ele não tenta
reunir tudo o que importa em engenharia de software e não pretende transformar
DRY, YAGNI ou KISS em fatores
([FAQ oficial da atualização](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).
Portanto, ele não substitui o Context Map, os ADRs, o modelo de durabilidade, a
segurança, o desenho da API ou a estratégia de testes do Leafcutter.

### A doutrina publicada e a revisão em andamento

Há três camadas que não devem ser misturadas:

1. O manifesto publicado contém os doze fatores e continua sendo a referência
   estável disponível em `12factor.net`.
2. A visão da atualização preserva a ideia de um contrato claro entre aplicação
   e plataforma e quer separar fatores, exemplos e recomendações operacionais
   ([visão oficial](https://github.com/twelve-factor/twelve-factor/blob/next/VISION.md)).
3. Os textos do branch `next` são trabalho em andamento. A FAQ reconhece que
   containers, Kubernetes e outras práticas se tornaram comuns, e que detalhes
   sobre observabilidade, segurança e configuração precisam ser modernizados
   ([FAQ oficial da atualização](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).

O ponto sensato é conservar os princípios e questionar exemplos datados. Env
vars, `stdout`, processos descartáveis e releases imutáveis continuam sendo
boas ferramentas mentais. Nenhuma delas, isoladamente, resolve secret
management, traces, supply chain, migrações sem downtime ou recuperação de
dados.

### Quatro termos que mudam de significado no Leafcutter

#### App

No manifesto, uma app possui uma codebase e muitos deploys. Se partes têm
codebases e ciclos de deploy independentes, o texto as considera aplicações de
um sistema distribuído ([fator I](https://12factor.net/codebase)).

Para o desenho atual, a unidade correspondente à app é a release homogênea do
Leafcutter, não cada OTP application. `leafcutter_core`,
`leafcutter_connectors`, `leafcutter_runtime` e `leafcutter_api` são divisões
internas propostas de uma mesma unidade de deploy
([umbrella e dependências](../architecture/umbrella-e-dependencias.md)). Se um
dia API e runtime ganharem releases independentes, cada release deverá ser
avaliada como uma app separada.

#### Process

No manifesto, process é uma instância da aplicação administrada pela plataforma
ou pelo sistema operacional. Um processo Erlang é outra coisa. Uma única BEAM
pode supervisionar milhares de processos Erlang e ainda corresponder a um único
processo da formação descrita pelo Twelve-Factor. O próprio fator de concorrência
permite multiplexação interna por threads, VMs ou modelos assíncronos, mas exige
que a aplicação também consiga ocupar várias instâncias e máquinas
([fator VIII](https://12factor.net/concurrency)).

#### Environment

No fator de configuração, environment é o conjunto de variáveis fornecidas a um
deploy. Em `Organizations`, `Environment` é uma entidade de domínio que separa
configuração e operação de um cliente, como homologação e produção
([contextos e ownership](../architecture/contextos-e-ownership.md)). Uma
release de produção pode atender muitos `Organizations.Environment`; esses
registros não devem virar milhares de env vars do processo.

#### Release

No Twelve-Factor, release é um build da plataforma combinado com a configuração
de um deploy. No Leafcutter, `PackageVersion`, `EnvironmentDeployment` e
`RunSnapshot` são artefatos e registros de domínio. Os dois eixos precisam de
identidades próprias. Uma release do Leafcutter pode executar muitas Package
Versions, e um Run Snapshot não identifica o binário da plataforma que o
processou.

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

## Avaliação fator a fator

### I. Codebase

O fator pede uma codebase versionada e muitos deploys. Desenvolvimento local,
staging e produção executam versões diferentes da mesma história de código
([fator I](https://12factor.net/codebase)).

O repositório atual evidencia uma única raiz Git, uma umbrella e um `mix.exs` no
topo. O ADR aceito escolheu poucas OTP applications e uma release homogênea
inicial ([ADR-0001](../decisions/ADR-0001-umbrella-com-poucas-apps.md)). O código
de Integration Packages ficará em `packages/`, separado de `apps/`, mas
participará inicialmente do mesmo build e da mesma release
([ADR-0007](../decisions/ADR-0007-integration-packages.md)). Isso é compatível
com uma codebase monorepo.

Ainda não há deploy. Também falta ratificar como `packages/` entra no build. O
fator não exige transformar cada context em repositório, app OTP ou
microservice. Fazer isso agora contrariaria a decisão de poucas applications e
criaria ciclos de release sem necessidade.

Critérios futuros de verificação:

- uma release deve apontar para um commit e um artifact ID reproduzíveis;
- development, homologation e production devem executar artefatos derivados da
  mesma codebase;
- nenhuma correção pode ser feita editando código dentro de uma instância em
  execução;
- se uma parte ganhar deploy independente, registrar explicitamente a nova
  unidade de app e reavaliar os fatores para ela.

### II. Dependencies

O fator exige declaração completa e isolamento de dependências. A aplicação não
deve depender de bibliotecas ou executáveis que "por acaso" existem na máquina
([fator II](https://12factor.net/dependencies)).

Há evidência parcial: `mix.exs` declara as dependências da raiz e `mix.lock`
congela resoluções. Credo e Dialyxir ficam fora do runtime. Tidewave e Bandit são
somente de desenvolvimento. O gate `mix quality` já verifica a umbrella
([quality gates](../implementation/quality-gates.md)).

O que falta:

- versão suportada de Erlang/OTP e Elixir versionada no repositório;
- dependências próprias das child applications, que ainda não existem;
- estratégia de dependências e compilação de Integration Packages;
- inventário de bibliotecas nativas, NIFs e pacotes do sistema operacional;
- build de produção que prove não depender do checkout ou do ambiente do
  desenvolvedor.

Uma release Mix pode empacotar código, ERTS e bibliotecas, mas o host de build e
o target ainda precisam ter arquitetura, ABI e bibliotecas de sistema
compatíveis. A documentação oficial também recomenda incluir ERTS e descreve
como NIFs e OpenSSL podem introduzir dependências do sistema
([`mix release`](https://hexdocs.pm/mix/Mix.Tasks.Release.html)). Portanto,
`mix.lock` é necessário, mas não basta para um build reproduzível.

### III. Config

Na doutrina original, config é tudo que varia entre deploys: handles de backing
services, credenciais e valores como hostname. Esse conteúdo deve ficar fora do
código e ser fornecido por controles ortogonais no environment
([fator III](https://12factor.net/config)).

O Leafcutter precisa classificar configuração antes de escolher o mecanismo:

| Classe | Exemplos no Leafcutter | Local conceitual |
|---|---|---|
| Config de deploy | URL do Postgres, host/porta da API, node name, cookie de distribuição, exporter de telemetry | Runtime config da release ou config provider |
| Config de domínio | PackageVersion, destinations, batching permitido, schedules, overrides | Contexts e PostgreSQL, com ownership e histórico |
| Credencial de tenant | OAuth token, API key, SecretVersion | `Connections`, com provider/criptografia ainda pendentes |
| Decisão de build | módulos compilados, dependências, topology estática do pacote | Código e artefato versionado |

O fator se aplica diretamente à primeira linha. Ele não manda armazenar cada
Connection ou Integration em env vars. Esses dados variam por tenant e fazem
parte do domínio durável. O desenho ratificado de `Connections` separa dados
sensíveis de `Connection` e proíbe secrets em manifests, logs e respostas
([contextos e ownership](../architecture/contextos-e-ownership.md)).

Hoje só existe `config/config.exs`; não há `runtime.exs`, contrato de variáveis,
validação de boot ou secret provider. Essa é uma lacuna, mas a decisão física de
secrets e o provider de infraestrutura continuam explicitamente abertos
([decisões em aberto](../architecture/decisoes-em-aberto.md)). Releases Mix
executam `config/runtime.exs` no boot e também aceitam config providers para
fontes como vaults ou arquivos
([`mix release`, seção de runtime configuration](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-runtime-configuration)).

Critérios futuros:

- documentar nome, tipo, obrigatoriedade, valor seguro e momento de leitura de
  cada config de deploy;
- falhar cedo e sem imprimir secrets quando uma config obrigatória estiver
  ausente ou inválida;
- não ler config mutável de build em runtime;
- manter config de tenant nas APIs e tabelas dos contexts proprietários;
- decidir o mecanismo de secrets depois que o modelo de `Connections` e o
  ambiente de deploy forem conhecidos.

### IV. Backing services

O fator trata bancos, filas, caches, serviços de email e APIs remotas como
recursos anexados. Código e topologia não devem mudar quando um handle compatível
aponta para outra instância do mesmo tipo de serviço
([fator IV](https://12factor.net/backing-services)).

O Leafcutter já tem uma direção clara:

- PostgreSQL é a autoridade durável
  ([ADR-0004](../decisions/ADR-0004-estado-operacional-e-duravel.md));
- o backlog inicial também vive no Postgres, sem fila externa antecipada
  ([ADR-0010](../decisions/ADR-0010-fanout-duravel-sem-fila-externa.md));
- `Connections` representa e resolve acesso de uma Organization e Environment a
  sistemas externos, enquanto Connectors escondem protocolo e semântica da
  operação
  ([contextos e ownership](../architecture/contextos-e-ownership.md),
  [ADR-0008](../decisions/ADR-0008-connector-operation-transport.md)).

Isso é direção ratificada, não implementação. Provider, backups, topologia do
Postgres, object storage e fila externa continuam abertos ou futuros. Trocar uma
instância Postgres por outra compatível deve exigir mudança do handle, não do
código. Trocar Salesforce por um ERP com outro contrato não é uma simples troca
de backing service. Pode exigir outro Connector ou Package porque a semântica de
domínio mudou.

O fator também não justifica um repository pattern genérico. Ecto e APIs
públicas dos contexts já podem manter o recurso configurável sem esconder o
domínio atrás de uma camada extra.

### V. Build, release, run

O manifesto separa três estágios. Build transforma um commit em bundle
executável. Release combina build e config do deploy. Run inicia processos de
uma release imutável. Cada release deve ter identidade única e qualquer mudança
deve produzir outra release ([fator V](https://12factor.net/build-release-run)).

O projeto só tem uma proposta de release homogênea. Ainda faltam:

- CI para executar o gate já existente;
- build de produção e artifact store;
- identidade que relacione commit, release Mix e artefato implantado;
- estratégia física de compilação de `packages/`;
- ordem de migrations e deploy;
- rollback da plataforma;
- configuração de runtime;
- prova de que o boot não baixa schemas, dependencies ou código.

O desenho de Contracts ajuda: `$ref` remoto deve ser resolvido e congelado na
publicação, e um Run não dependerá da internet para interpretar seu schema
([contracts com JSON Schema](../architecture/contracts-json-schema.md)). Package
Versions imutáveis e Run Snapshots também aumentam reprodutibilidade do domínio.
Mesmo assim, eles não substituem a identidade da release da plataforma.

Uma trilha de execução completa deveria conseguir responder:

```text
commit da codebase
-> build ID e digest
-> release ID
-> deploy ID e config revision
-> BEAM node/release version
-> Run Snapshot
-> PackageVersion e ContractVersions
```

Essa cadeia não precisa virar um framework interno. Campos de provenance e
metadata operacional bastam quando o modelo concreto existir.

### VI. Processes

O fator diz que os processos da app são stateless e share-nothing. Memória e
filesystem local podem servir como cache transitório, mas a aplicação não pode
supor que esse conteúdo sobreviverá à próxima request, job, movimentação ou
reinício ([fator VI](https://12factor.net/processes)).

O baseline ratificado do Leafcutter combina bem com essa regra:

```text
PostgreSQL
-> estado durável, histórico, ownership, checkpoints e intenções

OTP e Broadway
-> estado operacional, concorrência, demand e lifecycle
```

Processos são reconstruíveis e o Postgres informa de onde continuar
([ADR-0004](../decisions/ADR-0004-estado-operacional-e-duravel.md)). Um cursor
mais avançado apenas na memória pode provocar replay após crash, e isso é parte
da semântica `at-least-once`
([durabilidade e recovery](../architecture/durabilidade-e-recovery.md)).

Há uma tensão com a leitura literal de "stateless e share-nothing" quando um
GenServer ou uma pipeline Broadway mantém estado operacional durante um Run
longo. Ainda assim, o desenho preserva o objetivo operacional do fator se toda
obrigação puder ser reconstruída depois da perda da BEAM. A incompatibilidade
grave surgiria se o sistema precisasse do PID, da mailbox, do ETS local ou do
filesystem de um node para recuperar a verdade do Run. Cache de validators
compilados em ETS também é aceitável se puder ser reconstruído a partir de
ContractVersions persistidas.

A prova futura não será uma leitura do diagrama. Ela exige testes que matem
processos e nodes durante ingestão, fan-out e delivery, depois verifiquem
reconstrução, replay seguro e ausência de avanço indevido do checkpoint.

### VII. Port binding

O fator pede uma aplicação autocontida que exporte seu serviço ao escutar uma
porta, sem depender de injeção de um webserver pelo ambiente
([fator VII](https://12factor.net/port-binding)).

`leafcutter_api` deverá conter Phoenix Endpoint, autenticação da API e endpoints
de health/readiness, mas tanto a app quanto suas boundaries ainda são proposta
([umbrella e dependências](../architecture/umbrella-e-dependencias.md)). Bandit
aparece hoje apenas como dependência de desenvolvimento para `mix tidewave`; a
porta 4001 não é evidência de um serviço de produção.

Esse fator deve ser resolvido quando `leafcutter_api` for ratificada e criada:

- Endpoint e servidor HTTP empacotados na release;
- bind address e porta definidos por config de deploy;
- health e readiness com semânticas documentadas;
- proxy, TLS termination e load balancer externos ao código da app, salvo uma
  necessidade explícita;
- nenhuma hipótese de hostname fixo dentro do código.

Escolher Kubernetes ou outro provider não é requisito para atender ao fator.

### VIII. Concurrency

O manifesto expressa diversidade de workload por tipos de processo e escala por
quantidade de instâncias. Ele aceita concorrência interna à VM, mas espera que a
app também consiga atravessar processos e máquinas
([fator VIII](https://12factor.net/concurrency)).

O Leafcutter tem decisões fortes nessa área:

- Broadway controla demand, concorrência, batching e backpressure do data plane
  ([ADR-0005](../decisions/ADR-0005-broadway-como-data-plane.md));
- uma pipeline independente por destination isola destinos lentos
  ([runtime OTP e Broadway](../architecture/runtime-otp-broadway.md));
- nodes homogêneos são a primeira topologia, sem antecipar roles especializados
  ([cluster e infraestrutura](../architecture/cluster-e-infraestrutura.md));
- cada Run pertence a um node por vez, com `generation` como fencing token
  ([ADR-0011](../decisions/ADR-0011-run-ownership-fencing.md)).

Isso preserva a concorrência interna da BEAM sem depender de uma única BEAM para
escala total. A formação inicial pode ser apenas N nodes homogêneos. Separar API,
Oban e runtime em releases ou roles próprios só faz sentido após medir
contenção, como já determina o roadmap.

O risco principal não é deixar de criar mais tipos de worker. É afirmar escala
horizontal antes de testar claim concorrente, fairness entre tenants, limites
de pool do Postgres, capacity do backlog e recovery de ownership.

### IX. Disposability

Processos descartáveis iniciam rápido, encerram de forma graciosa e toleram
morte súbita. Workers devem devolver trabalho ou permitir sua recuperação, e
jobs precisam ser reentrantes ou idempotentes
([fator IX](https://12factor.net/disposability)).

O Leafcutter já aceitou os mecanismos mais importantes para morte súbita:

- `at-least-once` em vez de uma promessa universal de exactly-once
  ([ADR-0009](../decisions/ADR-0009-at-least-once.md));
- Records, Deliveries e checkpoint na mesma transação;
- leases/claims curtos, sem manter lock durante request externa;
- ownership recuperável e rejeição de generation antiga;
- supervisors para reconstruir processos.

Ainda há uma lacuna explícita: o processo concreto de graceful shutdown não foi
definido ([decisões em aberto](../architecture/decisoes-em-aberto.md)). Também
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

### X. Dev/prod parity

O fator pede pouca distância de tempo, pessoas e ferramentas entre
desenvolvimento e produção. Backing services devem manter tipo e versão tão
próximos quanto possível
([fator X](https://12factor.net/dev-prod-parity)).

O Leafcutter modela development, homologation e production como scopes de
cliente. Isso favorece promoção explícita e isolamento de Connections, mas não
prova paridade da plataforma
([ambientes, RBAC e homologação](../architecture/ambientes-rbac-homologacao.md)).

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

### XI. Logs

O manifesto trata logs como stream contínuo de eventos. A app escreve no stream
de saída, e a plataforma captura, roteia, indexa e retém esse conteúdo. O código
da app não gerencia arquivos de log
([fator XI](https://12factor.net/logs)).

O documento local de observabilidade separa corretamente três coisas:

- Execution Monitoring consulta Run, Records, Deliveries, Attempts e eventos
  duráveis;
- Platform Observability mede throughput, backlog, memória, DB e latência;
- AuditEvent registra ações humanas ou administrativas
  ([observabilidade e auditoria](../architecture/observabilidade-e-auditoria.md)).

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

### XII. Admin processes

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

## Onde o Twelve-Factor não basta para o Leafcutter

### Segurança

Separar config de código reduz vazamento acidental, mas não define criptografia,
controle de acesso, rotação, redaction ou resposta a incidente. A atualização
oficial cita segurança como uma área que precisa de recomendações modernas
([FAQ da atualização](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).
O Leafcutter deve continuar tratando `Connections`, SecretVersion, payload
access e permission matrix em seus próprios documentos e decisões.

### Durabilidade e semântica de integração

Os fatores dizem onde estado persistente deve ficar, mas não definem atomicidade
de fan-out, idempotency entre sistemas, sucesso parcial, retry ou fencing. Os
ADRs 0009, 0010 e 0011 são mais importantes para a correção do data plane do que
qualquer checklist genérico.

### Observabilidade completa

Enviar logs à saída padrão não produz metrics, traces, SLOs, alertas ou
diagnóstico de alta cardinalidade. A modernização oficial também reconhece
observabilidade como tema a atualizar. O Leafcutter já separa Execution
Monitoring de Platform Observability; precisa preservar essa separação na
implementação.

### Operação de dados

Backups, restore testado, retenção, migração de schema, object storage e
sequenciamento de deploy não são resolvidos pelos fatores. A topologia de
Postgres e backups continua aberta, enquanto retenção e externalização de
payloads são evoluções planejadas
([storage e retenção](../architecture/storage-e-retencao.md)).

### Workloads longos e stateful

A FAQ da atualização diz que o trabalho começa pela restrição simplificadora de
apps stateless orientadas a requests antes de ampliar para outros workloads
([FAQ oficial](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).
O Leafcutter combina API, schedules, jobs duráveis e Runs longos. Ele deve aplicar
o princípio de estado reconstruível, sem fingir que todo trabalho cabe no modelo
de request HTTP curta.

### Arquitetura interna

O Twelve-Factor não decide contexts, boundaries de OTP applications, APIs
públicas ou ownership de schemas. `Organizations`, `Catalog`, `Connections` e
`Integrations` continuam governados pelo Context Map e pelos ADRs locais. Usar
os fatores como desculpa para criar microservices, filas ou wrappers genéricos
seria uma leitura errada do método.

## Roadmap alinhado ao estado atual

Este roadmap ordena trabalho, mas não autoriza implementá-lo antes dos gates do
checkpoint. Em especial, nenhuma application, schema ou migration deve nascer
durante a ratificação de `Executions`.

### Etapa 0. Terminar o Context Map

Pré-requisito atual: nenhum.

Trabalho:

1. Ratificar a responsabilidade exata de `Executions`.
2. Ratificar `Notifications` e `Audit`.
3. Revisar ownership conjunto, APIs públicas e dependências.

Como o Twelve-Factor ajuda nesta etapa:

- `Executions` deve possuir verdade durável de Run sem transformar PID ou
  memória local em autoridade;
- `Notifications` precisa de obrigação durável, não apenas PubSub;
- `Audit` continua sink durável e não log operacional;
- nenhuma dessas conclusões define tabela, processo ou app OTP antecipadamente.

Evidência de conclusão: `CURRENT.md` e o Context Map marcam todos os contexts
como ratificados. Não há mudança de código.

### Etapa 1. Ratificar as boundaries das OTP applications

Pré-requisito: Context Map completo.

Decisões necessárias:

- confirmar se a unidade inicial de deploy é uma única release homogênea;
- fechar o grafo entre core, connectors, runtime e API;
- decidir ownership de Repo, migrations, PubSub e Oban;
- definir quais behaviours precisam atravessar boundaries de apps;
- manter `packages/` fora dos internals do runtime e da API.

Saída Twelve-Factor esperada: um pequeno documento de contrato app/plataforma
que declare codebase, unidade de build, unidade de release e tipos de processo.
Esse documento pode virar ADR apenas depois de discussão e ratificação.

Evidência de conclusão: grafo aceito, sem ciclos, refletido em `CURRENT.md`.

### Etapa 2. Fechar o contrato de build e configuração da Foundation

Pré-requisito: boundaries das apps ratificadas.

Entregáveis de desenho:

- versões suportadas de Erlang/OTP e Elixir;
- build target e dependências de sistema;
- esquema de release ID e relação com commit;
- taxonomia de build-time versus runtime config;
- catálogo inicial de env vars e resource handles;
- comportamento de boot diante de config inválida;
- estratégia inicial para compilar Integration Packages na release;
- comando de migration/one-off e sequência de deploy;
- decisão de port binding e health/readiness;
- contrato mínimo de logs e redaction.

Não é necessário escolher fila externa, Redis, object storage, roles separados ou
Kubernetes. O provider pode continuar aberto se o contrato não depender dele.

Evidência de conclusão: decisões ratificadas e critérios de aceitação anexados
ao primeiro marco. Ainda não se deve declarar conformidade operacional.

### Etapa 3. Criar a primeira release mínima

Pré-requisito: Etapa 2 e autorização de implementação.

Incrementos sugeridos:

1. Criar somente as OTP applications aprovadas, com supervision trees reais.
2. Fixar toolchain e declarar dependencies por app.
3. Adicionar CI para `mix quality`.
4. Produzir uma release Mix imutável com ID inspecionável.
5. Ler config de deploy no boot e validar valores obrigatórios.
6. Subir o Endpoint aprovado por port binding.
7. Emitir logs na saída padrão com redaction mínima.
8. Disponibilizar health/readiness com semântica testada.
9. Executar uma tarefa one-off versionada na mesma release.

Verificações:

- build em ambiente limpo;
- boot sem checkout e sem Mix no target;
- falha clara para config ausente;
- mesmo artefato iniciado com duas configurações não sensíveis distintas;
- SIGTERM encerra a application tree;
- logs não criam arquivo local nem expõem secret;
- CI executa formatter, compiler, Credo, testes e Dialyzer.

Essa etapa cobre a Foundation do
[roadmap arquitetural](../architecture/roadmap.md) e o
[primeiro marco](../implementation/first-milestone.md).

### Etapa 4. Provar os fatores no vertical slice V1

Pré-requisito: release mínima e contexts básicos implementados.

Trabalho:

- usar PostgreSQL do mesmo tipo e versão em desenvolvimento, CI, homologação e
  produção;
- persistir Run Snapshot e provenance da release;
- construir fan-out durável dentro de transação;
- provar restart de Source e Destination Broadway;
- provar replay `at-least-once` e idempotency quando suportada;
- tratar Connections como recursos configurados, sem credencial no código;
- validar que ContractVersions e PackageVersions são congeladas antes do run;
- expor o workflow administrativo pelo Endpoint da release.

Evidência de conclusão: testes de crash/restart, atomicidade, concorrência e
contrato, além de um deploy de homologação usando o artefato que poderá ser
promovido.

### Etapa 5. Endurecer operação em V1.x

Pré-requisito: V1 funcional e métricas reais.

Trabalho:

- definir e testar graceful shutdown de API, Oban e Broadways;
- estabelecer startup e readiness budgets;
- testar rolling deploy e recovery de node;
- completar logs estruturados, metrics, traces, alertas e correlação;
- testar troca e restore de backing resources;
- automatizar migrations e rollback compatível;
- definir secret provider, rotation e redaction;
- medir pool, backlog, throughput, storage e fairness.

Fila externa, node roles especializados e stores adicionais só entram se as
métricas confirmarem os gargalos previstos no roadmap.

### Etapa 6. Reavaliar a cada mudança de unidade de deploy

Gatilhos para nova avaliação:

- API e runtime passam a releases independentes;
- Integration Packages viram artefatos carregados fora da release;
- aparece uma fila externa;
- object storage passa a guardar payloads;
- nodes ganham roles diferentes;
- a versão revisada do manifesto Twelve-Factor é oficialmente publicada.

Cada gatilho pode mudar codebase, dependencies, config, backing services,
process formation e release lifecycle. A resposta não deve ser copiar esta
avaliação. O agente precisa observar a implementação e atualizar a conclusão.

## Backlog orientado a evidências para agentes

As tarefas abaixo são futuras. O campo "quando" é um gate, não uma sugestão para
começar imediatamente.

| ID | Quando | Tarefa | Evidência de aceitação | Fatores |
|---|---|---|---|---|
| TF-01 | Após Context Map | Definir a unidade inicial de app/deploy | ADR ou decisão ratificada, grafo sem ciclos e `CURRENT.md` atualizado | I, V, VIII |
| TF-02 | Após apps ratificadas | Versionar toolchain e inventariar dependencies de sistema | Build limpo documentado, versões fixadas, nenhum executável implícito | II, X |
| TF-03 | Antes da primeira release | Classificar config de build, deploy, domínio e secrets | Catálogo com owner, fonte, validação e redaction | III, IV |
| TF-04 | Antes da primeira release | Definir artifact/release ID e provenance | Release aponta para commit e digest; Run pode registrar release version | I, V |
| TF-05 | Na criação da API | Definir port binding e probes | Endpoint autocontido, porta configurável, health/readiness testados | VII, IX |
| TF-06 | Na criação do Repo | Definir migration e one-off lifecycle | Comando da release, mesma config, execução repetível e falha observável | V, XII |
| TF-07 | No primeiro runtime | Escrever crash matrix | Testes cobrem processo, node, pre/post-commit e stale generation | VI, IX |
| TF-08 | Antes do primeiro deploy | Definir logging contract | `stdout`/`stderr`, metadata, níveis, redaction e captura externa | XI |
| TF-09 | Antes de produção | Definir parity matrix | Toolchain e backing service type/version comparados por ambiente | X |
| TF-10 | Em V1.x | Provar graceful shutdown | SIGTERM, drain, reclaim e rolling deploy passam em teste | IX |
| TF-11 | Em V1.x | Validar resource replacement e restore | Troca de handle e restore ensaiados sem mudança de código | IV, X |
| TF-12 | Após métricas | Reavaliar process formation | Decisão baseada em throughput, backlog, DB pool e isolamento medidos | VIII |

## Checklist para uma futura revisão

Um agente que revisar o Leafcutter contra o Twelve-Factor deve responder com
evidência, não com a intenção do documento:

### Codebase e build

- Qual commit gerou o artefato?
- O build começa em ambiente limpo e usa apenas dependencies declaradas?
- A release tem ID único e é imutável?
- O runtime baixa ou compila algo que deveria ter sido resolvido no build?

### Config e recursos

- O que varia por deploy e de onde cada valor vem?
- Config inválida impede boot com erro seguro?
- Config de tenant continua no context proprietário?
- Backing service pode ser substituído por handle sem editar código?
- Secrets aparecem em logs, manifests, Run Snapshots públicos ou erros?

### Runtime

- Que estado se perde quando a BEAM morre?
- O Postgres contém informação suficiente para reconstruir cada obrigação?
- Duas instâncias podem executar trabalho concorrente sem stale owner gravar?
- A aplicação escala para N nodes sem sticky session ou filesystem compartilhado?

### Deploy e operação

- O mesmo artefato atravessa homologação e produção?
- A API escuta uma porta configurável e tem readiness honesta?
- SIGTERM e SIGKILL preservam as invariantes duráveis?
- Logs vão para streams e não substituem AuditEvent ou ExecutionEvent?
- Migrations e one-offs usam a mesma release e config?

### Limites da conclusão

- A avaliação distingue código observado, decisão ratificada e proposta?
- O fator está sendo usado fora de seu escopo?
- A recomendação cria infraestrutura antes de existir uma necessidade medida?
- O checkpoint autoriza essa etapa?

## Conclusão

O Twelve-Factor oferece ao Leafcutter uma boa lista de perguntas sobre a borda
operacional da aplicação. Ele é particularmente valioso porque a documentação
local está forte no domínio e no runtime, mas ainda não fechou como um commit se
torna uma release configurada, observável, reiniciável e administrável.

O melhor uso agora é como restrição de planejamento. A ratificação de
`Executions` deve preservar estado durável e runtime reconstruível. A
ratificação das OTP applications deve declarar a unidade real de deploy. Depois,
a Foundation deve fechar config, build, release, porta, logs e one-offs antes de
prometer portabilidade ou operação em cluster.

Não há motivo para adicionar containers, Kubernetes, filas ou abstrações
genéricas por causa desta pesquisa. Uma release Mix única, Postgres como recurso
durável, nodes homogêneos e contratos pequenos podem atender bem aos princípios
originais. O trabalho difícil é provar o comportamento em boot, crash, deploy e
recovery. Essa prova virá de artefatos e testes, não de uma etiqueta
"Twelve-Factor".

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

- [Checkpoint atual](../checkpoint/CURRENT.md)
- [Índice de ADRs](../decisions/README.md)
- [Contextos e ownership](../architecture/contextos-e-ownership.md)
- [Umbrella e dependências](../architecture/umbrella-e-dependencias.md)
- [Runtime OTP e Broadway](../architecture/runtime-otp-broadway.md)
- [Durabilidade e recovery](../architecture/durabilidade-e-recovery.md)
- [Cluster e infraestrutura](../architecture/cluster-e-infraestrutura.md)
- [Observabilidade e auditoria](../architecture/observabilidade-e-auditoria.md)
- [Decisões em aberto](../architecture/decisoes-em-aberto.md)
- [Roadmap arquitetural](../architecture/roadmap.md)
- [Sequência de implementação](../implementation/sequence.md)
- [Quality gates](../implementation/quality-gates.md)
