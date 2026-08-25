# Cluster BEAM e infraestrutura

## Modelo cru inicial

```text
Internet
   ↓
Load Balancer
   ↓
BEAM nodes homogêneos
   ↓
PostgreSQL
```

Cada máquina/container executa inicialmente uma release e um BEAM node.

## Nodes homogêneos

Todos os nodes começam com:

- API Phoenix;
- Core contexts;
- Oban configurado;
- Runtime OTP/Broadway;
- Connectors.

Não separar API workers e runtime workers antes de medir contenção real.

## Distribuição Erlang

Nodes usam rede privada e discovery, possivelmente DNSCluster quando o ambiente for escolhido.

Distributed Erlang serve para:

- cluster PubSub;
- comunicação operacional entre nodes;
- `nodeup`/`nodedown`;
- visibilidade de membership.

Não serve como:

- banco;
- fila durável;
- ownership definitivo de Run;
- substituto de Postgres;
- justificativa para espalhar processos de um mesmo Run entre nodes.

## Regra inicial de placement

```text
A Run belongs to one node.
```

Coordinator, Source, Enrichments e Destinations daquele Run ficam juntos. Distribuir branches individualmente é evolução futura, não premissa.

## Segurança

- portas de distribuição nunca expostas à internet;
- cookie armazenado como secret;
- rede privada;
- TLS para distribuição se o ambiente exigir;
- Postgres não público;
- secrets fora de manifests/logs.

## Escala

Escala horizontal inicial:

```text
1 node
→ 2 nodes
→ N homogeneous nodes
```

Adicionar nodes aumenta capacidade de API, Oban e Runs concorrentes.

## Evolução

Somente após métricas:

```text
homogeneous nodes
→ specialized API/runtime nodes
→ object storage
→ package artifact isolation
→ analytics store
→ external queue if justified
```

BEAM cluster não é Kubernetes. É um conjunto de runtimes excelentes em supervisionar e comunicar processos concorrentes.
