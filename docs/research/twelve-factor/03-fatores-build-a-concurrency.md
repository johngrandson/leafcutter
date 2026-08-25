# Fatores V a VIII: release, processos, porta e concorrência

> Pesquisa realizada em 25 de agosto de 2026. Material de aprendizagem e
> apoio ao planejamento. Não é um ADR, não ratifica decisões arquiteturais e
> não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

[Voltar ao índice](README.md)

## V. Build, release, run

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
([contracts com JSON Schema](../../architecture/contracts-json-schema.md)). Package
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

## VI. Processes

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
([ADR-0004](../../decisions/ADR-0004-estado-operacional-e-duravel.md)). Um cursor
mais avançado apenas na memória pode provocar replay após crash, e isso é parte
da semântica `at-least-once`
([durabilidade e recovery](../../architecture/durabilidade-e-recovery.md)).

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

## VII. Port binding

O fator pede uma aplicação autocontida que exporte seu serviço ao escutar uma
porta, sem depender de injeção de um webserver pelo ambiente
([fator VII](https://12factor.net/port-binding)).

`leafcutter_api` deverá conter Phoenix Endpoint, autenticação da API e endpoints
de health/readiness, mas tanto a app quanto suas boundaries ainda são proposta
([umbrella e dependências](../../architecture/umbrella-e-dependencias.md)). Bandit
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

## VIII. Concurrency

O manifesto expressa diversidade de workload por tipos de processo e escala por
quantidade de instâncias. Ele aceita concorrência interna à VM, mas espera que a
app também consiga atravessar processos e máquinas
([fator VIII](https://12factor.net/concurrency)).

O Leafcutter tem decisões fortes nessa área:

- Broadway controla demand, concorrência, batching e backpressure do data plane
  ([ADR-0005](../../decisions/ADR-0005-broadway-como-data-plane.md));
- uma pipeline independente por destination isola destinos lentos
  ([runtime OTP e Broadway](../../architecture/runtime-otp-broadway.md));
- nodes homogêneos são a primeira topologia, sem antecipar roles especializados
  ([cluster e infraestrutura](../../architecture/cluster-e-infraestrutura.md));
- cada Run pertence a um node por vez, com `generation` como fencing token
  ([ADR-0011](../../decisions/ADR-0011-run-ownership-fencing.md)).

Isso preserva a concorrência interna da BEAM sem depender de uma única BEAM para
escala total. A formação inicial pode ser apenas N nodes homogêneos. Separar API,
Oban e runtime em releases ou roles próprios só faz sentido após medir
contenção, como já determina o roadmap.

O risco principal não é deixar de criar mais tipos de worker. É afirmar escala
horizontal antes de testar claim concorrente, fairness entre tenants, limites
de pool do Postgres, capacity do backlog e recovery de ownership.
