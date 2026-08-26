# Umbrella e dependências

> **Status: RATIFICADO E MATERIALIZADO.** As quatro OTP applications existem no repositório e o grafo de dependências entre elas já está expresso nos respectivos `mix.exs`.

## Objetivo

Usar poucas OTP applications com boundaries operacionais reais, sem transformar cada context em uma app e sem antecipar microservices.

Estrutura inicial:

```text
apps/
├── leafcutter_core/
├── leafcutter_connectors/
├── leafcutter_runtime/
└── leafcutter_api/
```

Todas as quatro applications possuem supervision tree desde sua criação.

Contexts não recebem supervisors vazios próprios.

---

# `leafcutter_core`

## Responsabilidade

Hospedar os contexts de domínio que não pertencem ao runtime data plane:

```text
Organizations
Catalog
Connections
Integrations
Notifications
Audit
```

Também hospeda infraestrutura compartilhada da release:

```text
Leafcutter.Repo
Leafcutter.PubSub
Oban
```

## Repo

Existe um único `Leafcutter.Repo` compartilhado pela release.

Não criar Repo por app ou por context.

As migrations ficam centralizadas em:

```text
apps/leafcutter_core/priv/repo/migrations/
```

Isso inclui migrations de tabelas cujo ownership de domínio pertence a `Executions` em `leafcutter_runtime`.

Localização física da migration não altera ownership conceitual do schema.

## PubSub

`Leafcutter.PubSub` pertence à infraestrutura compartilhada de core.

Uso:

```text
ephemeral facts
live operational propagation
non-durable notifications inside the running system
```

PubSub não substitui representação durável de trabalho ou eventos obrigatórios.

## Oban

Oban é compartilhado e iniciado por core.

Usos apropriados iniciais:

```text
scheduling
notifications
maintenance
durable future work
```

`Delivery` do runtime não vira automaticamente Oban job.

## Dependências entre Leafcutter apps

```text
none
```

`leafcutter_core` é foundational.

---

# `leafcutter_connectors`

## Responsabilidade

Hospedar código executável e contracts de integração com sistemas externos:

- Connector behaviours;
- Operation behaviours;
- Transport behaviours;
- HTTP Transport inicial;
- Generic HTTP Connector;
- connector implementations;
- shared transport infrastructure quando necessária.

## O que não pertence aqui

```text
domain Contexts
persistent domain schemas
Run state
Integration state
API controllers
```

A metadata/versioning de connectors pertence a `Catalog`; implementação executável pertence aqui.

Não criar GenServer por Connector apenas para representar configuração.

Processos supervisionados entram somente quando transport infrastructure realmente exigir lifecycle, pool, coordenação ou state.

## Dependências entre Leafcutter apps

```text
none
```

`leafcutter_connectors` é foundational e independente de core.

---

# `leafcutter_runtime`

## Responsabilidade

Hospedar:

```text
Executions Context
+
runtime application workflows
+
OTP runtime infrastructure
```

## Runtime supervision

A application supervision tree evoluirá para:

```text
LeafcutterRuntime.Application
└── Supervisor
    ├── Registry
    ├── Run DynamicSupervisor
    └── NodeHeartbeat
```

Cada Run possui subtree própria:

```text
Run Supervisor
├── RunCoordinator
├── SourceBroadway
├── optional EnrichmentBroadway
└── DestinationBroadway x N
```

`RunCoordinator` permanece pequeno e atua no control plane do lifecycle do Run.

Record data e backlog não ficam concentrados nele.

Broadway é o data plane.

## Executions vs runtime infrastructure

`Executions` possui o domínio durável:

```text
Run
RunSnapshot
Record
Delivery
Attempt
Checkpoint
ExecutionEvent
ownership/fencing persistent state
```

A application runtime possui:

```text
Registry
DynamicSupervisor
NodeHeartbeat
RunCoordinator
Broadway pipelines
```

Não misturar os dois ownerships.

## Application workflows

Cross-context composition necessária para execução acontece aqui.

Exemplo conceitual de start de Run:

```text
Integrations.Deployments.get_execution_definition(...)
→ resolve Connections / credential refs
→ Executions creates Run + RunSnapshot
→ start Run subtree
```

O workflow pode consumir APIs públicas de contexts hospedados em core sem transformar `Executions` em dependente deles.

## Dependências entre Leafcutter apps

```text
leafcutter_runtime
├──→ leafcutter_core
└──→ leafcutter_connectors
```

Esse grafo já está materializado no `mix.exs`.

---

# `leafcutter_api`

## Responsabilidade

Phoenix HTTP adapter da plataforma:

- Endpoint;
- Router;
- controllers/plugs;
- API authentication;
- authorization na boundary;
- OpenAPI canônico;
- health/readiness;
- future inbound HTTP endpoints.

Não possui regra de negócio própria.

## Autorização

Fluxo conceitual:

```text
HTTP request
→ authenticate
→ Organizations.Access.authorize(...)
→ public workflow/context API
→ HTTP response
```

Não duplicar autorização em todos os contexts apenas por defesa arquitetural.

## Supervisão

O Phoenix Endpoint e Telemetry gerados são infraestrutura legítima da API application.

Não criar `AuthServer`, caches ou processes extras sem lifecycle real.

## Dependências entre Leafcutter apps

```text
leafcutter_api
├──→ leafcutter_core
└──→ leafcutter_runtime
```

Esse grafo já está materializado no `mix.exs`.

---

# Grafo final entre OTP applications

```text
                  leafcutter_api
                    /       \
                   v         v
       leafcutter_core   leafcutter_runtime
                              /       \
                             v         v
               leafcutter_core   leafcutter_connectors
```

Forma por dependências diretas:

```text
leafcutter_core       → none
leafcutter_connectors → none
leafcutter_runtime    → core + connectors
leafcutter_api        → core + runtime
```

Não existe ciclo.

A independência entre contexts de domínio continua válida dentro desse grafo de applications: uma OTP app pode hospedar application workflows que compõem contexts sem criar dependência domain-to-domain.

---

# Integration Packages

Localização ratificada:

```text
packages/
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib/
    └── test/
```

Cada Integration Package é um **Mix project independente**, fora de `apps/`.

Packages não são uma quinta platform application.

## Dependências permitidas

Um Package pode depender de `leafcutter_connectors` quando precisa implementar behaviours/operations públicos.

Não há dependência obrigatória de `leafcutter_core`.

Dependência de core só deve existir se surgir um contrato público concreto e estável que realmente pertença lá.

Packages não devem depender de:

```text
leafcutter_runtime internals
leafcutter_api
```

## Build inicial

Packages instalados serão compilados na mesma release inicial.

A estratégia física usada para incluir `packages/*` no dependency graph ainda está aberta.

Não adotar filesystem auto-discovery ou outro mecanismo implícito sem ratificação.

O objetivo é manter a composição da release explícita, auditável e simples.

---

# Release inicial

Uma única release foi ratificada:

```text
:leafcutter
```

Composição conceitual:

```text
Leafcutter release
├── leafcutter_core
├── leafcutter_connectors
├── leafcutter_runtime
├── leafcutter_api
└── installed Integration Packages
```

Todos os nodes executam a mesma release inicialmente.

```text
Node A → core + connectors + runtime + api
Node B → core + connectors + runtime + api
```

Não criar antecipadamente classes distintas de node:

```text
api-only
worker-only
control-plane-only
runtime-only
```

Especialização futura só entra após necessidade operacional medida.

---

# Boundaries operacionais ratificadas

## Shared persistence

```text
one Leafcutter.Repo
→ hosted by leafcutter_core
```

## Shared PubSub

```text
one Leafcutter.PubSub
→ hosted by leafcutter_core
```

## Shared durable jobs

```text
one Oban infrastructure
→ hosted by leafcutter_core
```

## Runtime execution

```text
Run OTP trees
→ hosted by leafcutter_runtime
```

## External protocol execution

```text
Connector / Operation / Transport implementation
→ leafcutter_connectors
```

## HTTP boundary

```text
Phoenix Endpoint / platform API
→ leafcutter_api
```

---

# Pontos ainda abertos

As seguintes decisões não bloqueiam a foundation atual:

- mecanismo físico de inclusão dos Integration Packages no build/release;
- cliente HTTP concreto e eventual pool strategy;
- configuração exata de Oban queues/plugins;
- schemas, tabelas, índices e migrations de domínio;
- mecanismo físico de durable cross-context facts/outbox;
- representação histórica concreta de EnvironmentDeployment;
- JSON Schema final de `manifest.json`.

Esses pontos devem ser resolvidos quando o primeiro use case real exigir cada mecanismo.
