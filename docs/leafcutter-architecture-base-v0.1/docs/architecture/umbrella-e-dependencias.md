# Umbrella e dependências

> **Status: PROPOSTA PARA RATIFICAÇÃO.** O projeto já é uma umbrella, mas as applications ainda não devem ser criadas antes da aprovação deste grafo.

## Objetivo

Usar poucas OTP applications com fronteiras reais, sem transformar cada context em uma app ou antecipar microservices.

## Apps propostas

```text
apps/
├── leafcutter_core/
├── leafcutter_connectors/
├── leafcutter_runtime/
└── leafcutter_api/
```

## `leafcutter_core`

Responsabilidades propostas:

- `Leafcutter.Repo`;
- contexts Organizations, Catalog, Connections, Integrations, Notifications e Audit;
- `Leafcutter.PubSub` compartilhado;
- configuração base de Oban na release inicial;
- structs e behaviours mínimos usados por Integration Packages;
- contratos de erro comuns quando realmente compartilhados.

Não deve depender de Runtime, Connectors concretos ou API.

## `leafcutter_connectors`

Responsabilidades propostas:

- behaviours de Connector, Operation e Transport;
- `Transport.HTTP` inicial;
- Generic HTTP Connector;
- Official/Custom Connector implementations compiladas;
- interpretação de autenticação, paginação, rate-limit metadata e erros externos;
- cliente HTTP/pool necessário ao Transport.

Dependência:

```text
leafcutter_connectors → leafcutter_core
```

O app pode registrar suas implementações no Catalog durante startup sem que Core dependa dos módulos concretos.

## `leafcutter_runtime`

Responsabilidades propostas:

- context Executions;
- local Registry;
- DynamicSupervisor de Runs;
- Run supervision trees;
- Source, Enrichment e Destination Broadway pipelines;
- node heartbeat;
- claim/recovery/fencing;
- checkpointing e durable fan-out;
- Telemetry do runtime.

Dependências:

```text
leafcutter_runtime → leafcutter_core
leafcutter_runtime → leafcutter_connectors
```

## `leafcutter_api`

Responsabilidades propostas:

- Phoenix Endpoint;
- controllers e plugs;
- autenticação da API da plataforma;
- autorização na borda, sem substituir checagem no domínio;
- OpenAPI canônico;
- health/readiness endpoints;
- Inbound Endpoints quando essa capacidade entrar;
- sem regra de negócio própria.

Dependências:

```text
leafcutter_api → leafcutter_core
leafcutter_api → leafcutter_runtime
```

## Integration Packages

```text
packages/
└── <package>/
```

Packages não são código da plataforma. Inicialmente participam do mesmo build/release, mas a estratégia física de compilação ainda deve ser ratificada.

Dependências permitidas propostas:

```text
Integration Package → leafcutter_core public package contracts
Integration Package → leafcutter_connectors public behaviours/operations
```

Packages não devem depender de internals do runtime ou API.

## Grafo

```text
                   leafcutter_api
                      /       \
                     v         v
          leafcutter_core   leafcutter_runtime
                    ^          /       \
                    |         v         v
                    └── leafcutter_connectors
```

Forma simplificada e correta:

```text
core
↑
connectors
↑
runtime
↑
api
```

A implementação precisa evitar ciclos e delegações vazias entre apps.

## Release inicial

Uma release homogênea contém todos os apps:

```text
Leafcutter release
├── core
├── connectors
├── runtime
└── api
```

Todos os nodes executam a mesma release inicialmente. Separação em control plane/runtime workers só acontece após necessidade medida.

## Pontos a ratificar

- localização e lifecycle exatos de Oban;
- estratégia física de compilação de `packages/`;
- se PubSub inicia em Core ou API;
- quais behaviours públicos precisam realmente estar em Core;
- boundaries de Repo e migrations entre apps.
