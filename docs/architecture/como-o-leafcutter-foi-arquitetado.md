---
title: "Como o Leafcutter foi arquitetado"
subtitle: "Uma plataforma de integração confiável construída com Elixir, Phoenix, OTP e Broadway"
author: "Leafcutter Architecture Baseline"
date: "25 de agosto de 2026"
lang: pt-BR
toc: true
toc-depth: 3
numbersections: true
geometry: margin=2.2cm
fontsize: 11pt
mainfont: "DejaVu Sans"
monofont: "DejaVu Sans Mono"
colorlinks: true
linkcolor: blue
urlcolor: blue
---

# Introdução

O Leafcutter é uma plataforma para construir e operar integrações entre sistemas.

A ideia central é simples:

```text
System A
   ↓ extract once
validated data
   ├── transform for System B → batch → deliver to B
   └── transform for System C → batch → deliver to C
```

A simplicidade do desenho não elimina os problemas reais. Sistemas externos possuem formatos diferentes, autenticação, paginação, rate limits, respostas parciais, indisponibilidade e IDs incompatíveis. Uma execução pode atravessar milhões de registros e vários destinos. Um node pode cair no meio do processo. Um destination pode permanecer fora do ar enquanto os demais continuam saudáveis.

A arquitetura do Leafcutter foi desenhada para lidar com esses problemas sem transformar o projeto em uma coleção de frameworks internos. O objetivo é usar as primitives corretas do ecossistema Elixir e manter o código compreensível para um desenvolvedor que deseja dominá-lo ponta a ponta.

Este documento explica as peças do Leafcutter, a responsabilidade de cada uma e como elas trabalham juntas.

## Estado do documento

Esta é uma baseline arquitetural. Ela separa:

- decisões já aceitas;
- propostas que ainda serão ratificadas context por context;
- evoluções futuras que não devem influenciar a implementação inicial.

A arquitetura não deve ser tratada como desculpa para antecipar código. O repositório cresce por vertical slices pequenos, documentados e testáveis.

# O caso mais simples

Considere uma empresa que possui clientes em um ERP e precisa distribuí-los para um CRM e um sistema financeiro.

O ERP entrega:

```json
{
  "id": 42,
  "name": "Maria Silva",
  "age": 17,
  "email": "maria@example.com",
  "credit_limit": 5000
}
```

O CRM espera:

```json
{
  "external_id": "42",
  "full_name": "Maria Silva",
  "access_allowed": false
}
```

O sistema financeiro espera:

```json
{
  "customer_code": 42,
  "customer_name": "Maria Silva",
  "credit_limit": 5000
}
```

O Leafcutter extrai Maria uma vez e cria duas responsabilidades independentes:

```text
                       ┌── CRM
ERP Customer 42 ───────┤
                       └── Billing
```

Cada branch possui seu próprio contrato, Transformation, batching, rate limit, concorrência, retries e histórico.

Se Billing estiver fora do ar:

```text
CRM       completed
Billing   pending / retrying
```

CRM continua. Billing volta a processar quando estiver disponível. O dado não precisa ser buscado novamente do ERP apenas porque um destino falhou.

Esse exemplo pequeno contém quase toda a arquitetura.

# Princípios que orientam o desenho

## Usar a menor primitive correta

A ordem de preferência é:

```text
Elixir/Erlang standard library
→ OTP
→ Phoenix/Ecto/PubSub/Broadway/Oban
→ plain module/function
→ custom abstraction only when necessary
```

Isso não significa usar OTP em tudo. Um processo só existe quando há estado ao longo do tempo, lifecycle, mensagens, coordenação, concorrência ou isolamento de falha.

Transformar um payload é uma função. Controlar o lifecycle de um Run é um problema OTP. Mover milhões de mensagens com demand e batching é um problema Broadway. Guardar checkpoint é um problema de persistência.

## Funções puras no centro, efeitos nas bordas

A lógica específica de integração deve ser fácil de testar:

```elixir
@spec transform(map(), map()) ::
        {:ok, map()}
        | {:ok, [map()]}
        | :skip
        | {:error, term()}
def transform(customer, config) do
  {:ok,
   %{
     "external_id" => Integer.to_string(customer["id"]),
     "full_name" => customer["name"],
     "access_allowed" => customer["age"] >= config["minimum_age"]
   }}
end
```

Essa função não conhece HTTP, Repo, Oban, PubSub ou secrets.

## Estado operacional e estado durável

```text
OTP/Broadway
→ o que está acontecendo agora

PostgreSQL
→ de onde podemos continuar se tudo desaparecer
```

Supervisor reinicia um processo. PostgreSQL reconstrói o trabalho que o processo estava realizando.

## Contexts isolados

Phoenix Contexts são a principal unidade de organização do domínio. Context não é sinônimo de um arquivo gigante.

```text
Context root
→ operações sobre o conceito principal

Capability modules
→ capacidades públicas específicas

Internal modules
→ implementação privada
```

Outros contexts não acessam schemas, queries ou internals diretamente.

# As três unidades fundamentais: Package, Integration e Run

Muitos sistemas misturam código reutilizável, configuração de cliente e execução. O Leafcutter separa essas responsabilidades.

## Integration Package

Package é código versionado.

```text
Integration Package
├── manifest.json
├── JSON Schemas
├── Transformations
├── optional Enrichments
├── Interceptors
└── dependency versions
```

Ele descreve o que a integração faz, mas não contém credenciais ou URLs de produção.

## Integration

Integration é uma instância configurada do Package para um cliente e ambiente.

```text
Acme / Homologation
Customer Distribution
Package: customer_distribution@1.3.0
Source Connection: ERP HML
Destination Connection: CRM HML
```

Outra Integration pode usar o mesmo Package em produção com Connections diferentes.

## Run

Run é uma execução concreta.

Quando começa, o Leafcutter resolve:

- Package Version;
- Contract Versions;
- dependency versions;
- Connection references;
- defaults e overrides;
- batching;
- concurrency;
- Trigger metadata.

O resultado é um Run Snapshot imutável.

```text
Package defaults
+ Integration overrides
+ resolved versions
= Run Snapshot
```

Se alguém alterar a Integration enquanto o Run está ativo, o Run não muda.

# Catalog

O Catalog permite descobrir e versionar building blocks reutilizáveis.

```text
Catalog
├── Connectors
│   ├── Official Connectors
│   └── Custom Connectors
├── Operations
├── Contracts
└── Integration Packages
```

O Catalog não executa o fluxo. Ele controla identidade, versões, dependências e disponibilidade.

Um Official Connector é mantido pela plataforma. Um Custom Connector representa um sistema específico. Para APIs REST simples, o Generic HTTP Connector evita criar código novo.

# Contracts com JSON Schema

Tudo que entra ou sai de uma integração é tratado como JSON ou como uma representação compatível com JSON dentro do Elixir.

JSON Schema Draft 2020-12 define a estrutura válida.

```text
untrusted external payload
    ↓
source JSON Schema / JSV
    ↓
trusted Elixir map
    ↓
Transformation
    ↓
candidate output
    ↓
destination JSON Schema / JSV
    ↓
valid payload
```

## Por que validar as duas pontas

O Source Contract protege o runtime contra dados externos inesperados.

O Destination Contract protege o sistema externo contra bugs no próprio Package.

Se a Transformation esquecer um campo obrigatório, a falha ocorre antes do HTTP e é registrada como erro de validação.

## Contratos versionados

Contracts são imutáveis. Um Run histórico continua explicável mesmo que o contrato atual tenha evoluído.

## Compilação

O schema é compilado uma vez e reutilizado. Não interpretar o mesmo JSON Schema para cada Record.

```text
Contract Version
→ compiled JSV validator
→ cache
→ many validations
```

Referências remotas são resolvidas e congeladas antes da execução. Um Run nunca depende da internet para compreender seu contrato.

# Connector, Operation e Transport

Esta separação impede que o runtime genérico seja contaminado por detalhes de HTTP ou de um fornecedor específico.

```text
Connector
→ understands the external system

Operation
→ understands one action

Transport
→ understands the protocol
```

## Connector

Um Salesforce Connector pode conhecer:

- OAuth;
- base URL conventions;
- default headers;
- common errors;
- rate-limit headers;
- Operations disponíveis.

Ele não conhece Acme nem a Transformation de um Package.

## Read Operation

Uma Operation de leitura normaliza paginação:

```elixir
fetch(config, cursor)
```

retorna:

```elixir
{:ok,
 %{
   records: [...],
   next_cursor: next_cursor,
   done?: false,
   metadata: %{}
 }}
```

O Source Broadway não precisa saber se a API usa `page`, `offset`, cursor ou `next_url`.

## Write Operation

A Operation de escrita recebe um batch já transformado e validado. Ela preserva resultado por item.

```elixir
{:ok,
 [
   %{status: :success, destination_identity: "CRM-9001"},
   %{status: :error, error: operation_error}
 ]}
```

Isso é necessário porque APIs de batch podem aceitar 99 registros e rejeitar apenas um.

## Transport

HTTP é o primeiro Transport. A arquitetura não pressupõe que será o único.

No futuro, Database, SFTP ou outros Transports podem implementar o mesmo modelo sem alterar Run, Record ou Delivery.

# Source Identity, Payload Hash e IdentityMapping

Três conceitos parecidos precisam permanecer separados.

## Record ID

Identifica a ocorrência interna dentro de um Run.

## Source Identity

Identifica a entidade estável no sistema de origem.

Uma Operation conhecida sabe extrair sua identity. Generic HTTP pode declarar algo simples:

```json
"identity": "id"
```

ou chave composta:

```json
"identity": ["company_id", "customer_id"]
```

## Payload Hash

Representa o conteúdo atual.

```text
same Source Identity
+ different Payload Hash
= same entity, changed data
```

## IdentityMapping

Relaciona a mesma entidade entre sistemas.

```text
ERP Customer 42
├── CRM Customer CRM-9001
└── Billing Customer BILL-710
```

Isso permite update/upsert no próximo Run e reduz duplicatas.

# Transformation

Transformation monta o payload de negócio.

Ela pode:

- renomear campos;
- combinar strings;
- fazer cálculos;
- aplicar regras condicionais;
- criar estruturas aninhadas;
- normalizar datas;
- decidir `:skip`;
- produzir vários payloads.

Retornos:

```text
{:ok, payload}       1 -> 1
{:ok, [payloads]}    1 -> N
:skip                1 -> 0
{:error, reason}     controlled failure
```

Não suporta N->1, joins ou aggregation stateful. Esses problemas exigem outra primitive futura.

# Enrichment

Às vezes o payload precisa de uma consulta externa antes da Transformation.

Exemplos:

- risk score;
- currency rate;
- inventory lookup;
- external code resolution;
- address metadata;
- product metadata.

Essa request on-the-fly não deve ficar escondida dentro de `transform/2`.

```text
validated source
    ↓
Enrichment preparation
    ↓
Connector Operation side effect
    ↓
persisted enrichment result
    ↓
Transformation
```

Enrichment é durável e retryable. No runtime, ele é uma Broadway pipeline opcional dentro da árvore do Run.

Se B e C precisam do mesmo resultado, o Enrichment acontece uma vez antes do fan-out. Enrichment específico por destination pode ser adicionado depois sem alterar a primitive.

# Interceptor

Interceptor adapta a comunicação, não o dado de negócio.

Casos:

- correlation ID;
- custom header;
- query parameter;
- signing;
- URL adjustment;
- tracing metadata.

```text
valid destination payload
    ↓
Operation builds request
    ↓
explicit Interceptors
    ↓
Transport
```

Na primeira arquitetura, Interceptor não modifica o body depois da validação do Destination Contract.

Interceptors globais invisíveis são evitados. O Package declara explicitamente quais Interceptors participam de cada destination.

# O modelo de execução

## Run supervision tree

```text
RunDynamicSupervisor
└── RunSupervisor <run_id>
    ├── RunCoordinator
    ├── SourceBroadway
    ├── optional EnrichmentBroadways
    └── DestinationBroadways
        ├── CRM
        └── Billing
```

A árvore de supervisão representa os principais lifecycles e failure domains do Run.

## RunCoordinator

O Coordinator controla:

- start;
- pause;
- resume;
- cancel;
- conclusão da source;
- conclusão/falha de destinations;
- conclusão do Run.

Ele não recebe uma mensagem por Record. Não faz HTTP. Não transforma payload. Não é gargalo do data plane.

## Broadway como data plane

Broadway já oferece producer, processors, batchers, demand, backpressure e supervision. O Leafcutter não cria managers e workers próprios para duplicar essas responsabilidades.

Source, Enrichment e cada destination possuem pipelines independentes quando necessário.

# Fan-out durável

O Leafcutter persiste o trabalho antes de entregá-lo aos destinations.

Para mil Records e dois destinos:

```text
1,000 Records
2,000 Deliveries
1 Checkpoint advancement
```

são persistidos em batch na mesma transação.

```text
Source Broadway
    ↓ validate page
build Records + Deliveries
    ↓
Postgres transaction
├── insert Records
├── insert Deliveries
└── advance Checkpoint
    ↓ COMMIT
```

Se a transação falha, o checkpoint não avança.

## Por que não usar fila externa primeiro

Broadway já controla demand e batching. Bulk inserts reduzem pressão. Uma fila antes do Postgres absorveria bursts, mas adicionaria infraestrutura e não eliminaria a necessidade de persistir o mesmo volume.

A primeira versão mede Postgres. Kafka, RabbitMQ ou outro broker entram somente se as métricas demonstrarem que o durable backlog em Postgres é o gargalo dominante.

`Delivery` permanece parte do domínio mesmo se o mecanismo de transporte mudar no futuro.

# Destination pipelines

Cada destination consome suas Deliveries de forma independente.

```text
Postgres
├── CRM Deliveries
└── Billing Deliveries

CRM Broadway      Billing Broadway
    ↓                  ↓
transform           transform
validate            validate
batch 100           batch 500
send CRM            send Billing
```

Um destination lento acumula backlog próprio. Os demais continuam.

## Claim

O Producer faz claim atômico de Deliveries disponíveis em transação curta, por exemplo usando uma estratégia baseada em `FOR UPDATE SKIP LOCKED`.

O lock não permanece aberto durante a request externa.

## Retry

Uma Delivery retryable retorna a:

```text
status = pending
available_at = future timestamp
attempt_count += 1
```

O Producer só busca trabalho disponível.

Oban não precisa representar milhões de Deliveries. Ele permanece responsável por schedules, notifications, maintenance e outros trabalhos futuros duráveis.

# Error model

Operations traduzem erros externos para uma taxonomia pequena:

```text
validation
authentication
rate_limited
timeout
temporary
permanent
```

Decisões:

```text
validation      no automatic retry
authentication  blocked until config/secret changes
rate_limited    retry later
timeout         retry
temporary       retry
permanent       no automatic retry
```

Partial batch success é preservado por Delivery. Uma request 429 para o batch inteiro não confirma nenhum item.

# At-least-once

O Leafcutter assume que trabalhos podem ser repetidos.

Exemplo crítico:

```text
CRM accepted request
    ↓
node crashed before local commit
    ↓
Leafcutter cannot prove completion
    ↓
retry
```

O sistema não promete exactly-once universal porque não controla a transação do CRM.

O efeito pode se tornar efetivamente único por:

- idempotency key;
- upsert;
- Source Identity;
- IdentityMapping;
- destination-specific support.

# Checkpoint

Checkpoint é estado durável, não processo OTP.

O Source Producer mantém cursor atual em memória. PostgreSQL guarda o último cursor seguro.

```text
runtime cursor = page 47
safe checkpoint = page 45
```

Crash pode repetir 46 e 47. Isso é consistente com `at-least-once`.

Não existe `CheckpointSupervisor` sem um lifecycle concreto que o justifique.

# Run ownership e recovery entre nodes

## Um Run, um node

Na primeira arquitetura, a árvore inteira de um Run vive em um node.

```text
Node A
└── Run 9182
    ├── Coordinator
    ├── Source
    ├── Enrichment
    ├── CRM
    └── Billing
```

Não espalhar branches individuais pelo cluster cedo.

## Heartbeat por node

```text
runtime_nodes
node_a heartbeat_at
node_b heartbeat_at
```

Run guarda:

```text
owner_node
generation
```

## Recovery

Se Node A desaparece e seu heartbeat expira, Node C pode claimar atomicamente o Run, incrementar generation e carregar snapshot/checkpoint.

```text
owner_node: node_a → node_c
generation: 4 → 5
```

Generation é fencing token. Escritas críticas de um owner antigo com generation 4 são rejeitadas.

Distributed Erlang oferece `nodedown` como sinal rápido, mas PostgreSQL continua sendo a autoridade.

Registry é local ao node e serve para localizar processos locais por Run ID.

# O cluster BEAM

## Infraestrutura inicial

```text
Internet
   ↓
Load Balancer
   ↓
BEAM Node A   BEAM Node B   BEAM Node C
        \        |        /
             PostgreSQL
```

Todos os nodes são homogêneos inicialmente. A mesma release contém Core, Connectors, Runtime e API.

## Distributed Erlang

Usado para:

- cluster PubSub;
- node membership;
- comunicação operacional;
- nodeup/nodedown.

Não usado como:

- banco;
- fila durável;
- ownership definitivo;
- motivo para criar distributed locks customizados.

Não usar `:global`, `:pg`, Horde ou CRDTs para ownership inicial de Runs.

## Evolução

Somente após métricas:

```text
homogeneous nodes
→ API/runtime specialization
→ object storage
→ package isolation
→ analytics store
→ external queue if justified
```

# Connections e Secrets

## Connection

Connection descreve acesso não sensível a um sistema em um Environment:

- Connector;
- base URL;
- account/region;
- timeouts defaults;
- referência ao Secret.

## Secret

Guarda:

- API keys;
- client secrets;
- refresh tokens;
- passwords;
- certificates.

Secrets são versionados, rotacionáveis e protegidos por RBAC. OAuth refresh que produz novo token é persistido de forma durável.

Nenhum secret entra em manifest, logs, AuditEvent ou Run Snapshot público.

# Environments, homologação e promoção

Package Versions são imutáveis. Environment controla configuração operacional.

```text
Package 1.4.0
    ↓ HML deployment
homologation Runs
    ↓ approval
promotion
    ↓ PROD deployment
```

Promoção não copia credenciais. HML e PROD usam suas próprias Connections e Secrets.

Rollback seleciona uma versão anterior e registra AuditEvent.

Homologation relaciona:

- versão testada;
- evidências/Runs;
- approver;
- target environment;
- resultado;
- timestamps.

# RBAC

Permissão é a primitive; Role é um agrupamento.

```text
who
→ User or ServiceAccount

what
→ Permission

where
→ Organization + Environment
```

Exemplos:

```text
integration.read
integration.write
integration.run
integration.approve
integration.promote
run.retry
run.cancel
secret.rotate
payload.read
audit.read
```

É possível ver status sem poder ler raw payloads.

Autorização não fica apenas no controller. Operações privilegiadas recebem actor/scope e aplicam policy na API do domínio.

# API-first

O Leafcutter será operável sem frontend.

```text
OpenAPI
├── platform documentation
├── Postman Collection
└── future SDKs
```

Postman não possui conhecimento exclusivo. SDKs só entram quando a API estiver estabilizada.

A API deve representar workflows completos:

```text
create Organization
→ create Environments
→ create Connections
→ publish Package Version
→ create Integration in HML
→ execute
→ inspect
→ approve
→ promote
→ execute in PROD
```

Inbound Endpoints entram como sources HTTP em uma release posterior. API Management completo é outro estágio do produto.

# Monitoring, observabilidade e auditoria

## Execution Monitoring

Consulta dados de domínio:

```text
Run
├── Records
├── Deliveries
├── Attempts
├── Enrichments
└── ExecutionEvents
```

## Platform Observability

Mede a plataforma:

- throughput;
- Broadway demand;
- backlog;
- DB latency;
- node health;
- memory;
- HTTP latency;
- rate-limit pressure.

## Attempt

Representa uma tentativa concreta de comunicação externa.

## ExecutionEvent

Representa fatos relevantes do Run, não cada mensagem interna.

## AuditEvent

Representa ações humanas/administrativas: promotion, rollback, secret rotation, manual retry, permission change.

## Notifications

Notification Rules reagem a eventos e usam Oban para entrega durável a Channels/Recipients. PubSub sozinho não garante notificação.

# Storage e retenção

O modelo lógico não obriga armazenamento quente eterno.

```text
PostgreSQL
→ operational truth and queryable metadata

Object Storage future
→ large immutable payloads

Analytics Store future
→ large historical aggregation
```

Na primeira versão, payloads podem ficar em JSONB por simplicidade. O modelo deve separar metadata de content para permitir externalização futura.

Payload access possui permissão específica. Request/response bodies antigos podem ter SLA assíncrono para audit export.

# Phoenix Contexts

A proposta inicial de Context Map é:

```text
Organizations
Catalog
Connections
Integrations
Executions
Notifications
Audit
```

Essa proposta ainda será ratificada um context por vez.

## Por que não um context por tabela

Run, Record, Delivery, Attempt e Checkpoint pertencem ao mesmo lifecycle de execução. Separá-los em cinco contexts criaria cerimônia e transações difíceis.

## Por que Executions não vira god module

A facade é segmentada:

```elixir
Executions.Runs.start(...)
Executions.Runs.pause(...)
Executions.Deliveries.retry(...)
Executions.Attempts.list(...)
Executions.Recovery.claim(...)
```

Schemas e implementação continuam internos.

# Apps da umbrella

Proposta inicial:

```text
apps/
├── leafcutter_core
├── leafcutter_connectors
├── leafcutter_runtime
└── leafcutter_api
```

## Core

Repo, contexts de negócio, PubSub e contracts públicos mínimos.

## Connectors

Connector/Operation/Transport behaviours e implementações.

## Runtime

Executions, Registry, DynamicSupervisor, Broadway, heartbeat e recovery.

## API

Phoenix Endpoint, controllers, auth, OpenAPI e Inbound APIs futuras.

Tudo sobe numa release inicialmente.

A divisão exata, incluindo Oban, PubSub, Repo e build de `packages/`, ainda será ratificada antes de criar as apps.

# Documentação como parte da arquitetura

Todo código e documentação in-code são em inglês.

Módulos públicos relevantes incluem:

```text
@moduledoc
@doc
@typedoc
@spec
named error contracts
```

A arquitetura fora do código permanece em pt-BR.

ExDoc é uma documentação técnica viva. Comentários explicam por que uma decisão incomum existe.

# Harness e continuidade

A conversa não é a memória canônica. O repositório é.

```text
AGENTS.md
→ regras permanentes para agentes

ADRs
→ decisões duráveis

Architecture docs
→ modelo e intenção

CURRENT.md
→ estado atual e próxima tarefa

Code + tests
→ comportamento real
```

O desenvolvedor é o autor principal. Codex atua por padrão em Guide Mode, Review Mode ou Debug Mode.

Uma nova sessão começa lendo:

1. `AGENTS.md`;
2. `CURRENT.md`;
3. ADRs relevantes;
4. código e testes atuais.

# Roadmap

## V0 - Foundation

Documentação, contexts, apps, Repo, CI, ExDoc e package spec.

## V1 - Reliable HTTP core

Generic HTTP, Packages, Contracts, one Source -> N Destinations, durable fan-out, Broadway, manual Runs, Attempts, IdentityMapping e API.

## V1.x - Reliability

Retries avançados, schedules, Enrichments, notifications, multi-node recovery e audit.

## V2 - Governance

RBAC, homologação, promotion/rollback, payload access e secret rotation.

## V3 - Ecosystem

Official/Custom Connectors, package tooling, dependency resolution, registry e OpenAPI import.

## V4 - Inbound e multi-transport

Inbound APIs, Database/SFTP transports, Codecs e object storage.

## V5+

Package isolation, specialized nodes, analytics, external queue somente se justificado, multi-source e SDKs após estabilização.

# O que ainda precisa ser ratificado

A baseline está sólida, mas os próximos passos são deliberadamente um por vez:

1. Context Map definitivo.
2. Ownership de conceitos/tabelas.
3. APIs públicas/capability modules.
4. Apps da umbrella e dependency graph.
5. Repo, PubSub e Oban placement.
6. Package compilation strategy.
7. Package Manifest JSON Schema v1.
8. Ecto schemas, states, constraints e indexes.
9. OpenAPI surface.
10. Runtime details de pause/cancel/shutdown/backlog limits.

# Conclusão

O Leafcutter usa a BEAM onde ela é forte sem transformar distribuição em objetivo próprio.

```text
OTP
→ lifecycle and fault isolation

Broadway
→ data flow, demand and batching

PostgreSQL
→ durable truth and recovery

Oban
→ durable future work

PubSub
→ ephemeral propagation

Phoenix
→ API and operational boundary

Ecto
→ constraints and persistence

JSON Schema + JSV
→ trustworthy data boundaries
```

A arquitetura procura manter duas qualidades ao mesmo tempo:

- um runtime capaz de lidar com concorrência, falhas e volume;
- um código que um desenvolvedor consiga abrir, ler e compreender sem depender de um agente para explicar cada camada.

Essa combinação é o critério central do Leafcutter.
