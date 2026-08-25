# Connectors, Operations e Transports

## Responsabilidades

```text
Connector
→ entende o sistema externo

Operation
→ entende uma ação específica

Transport
→ entende o protocolo
```

## Connector

Conhece comportamento compartilhado:

- auth scheme;
- base URL conventions;
- default headers/query params;
- common error parsing;
- rate-limit metadata;
- Operations disponíveis.

Não conhece cliente, Integration concreta ou Transformation.

## Operation de leitura

Contrato conceitual:

```elixir
fetch(config, cursor)
```

Resultado normalizado:

```elixir
{:ok,
 %{
   records: [...],
   next_cursor: cursor,
   done?: false,
   metadata: %{}
 }}
```

A Operation esconde paginação e formato externo.

## Operation de escrita

Recebe batch de payloads já transformados e validados.

O resultado preserva sucesso parcial por item:

```elixir
{:ok,
 [
   %{status: :success, destination_identity: "CRM-100"},
   %{status: :error, error: operation_error}
 ]}
```

Falhas da request inteira retornam erro da operação.

## Transport

A primeira implementação é `Transport.HTTP`. O runtime não deve assumir que toda integração é HTTP.

Futuros Transports:

- Database;
- SFTP;
- Kafka/RabbitMQ;
- object storage;
- SOAP-specific encoding sobre HTTP.

## Generic HTTP

Evita criar Custom Connector para APIs simples. Package configura apenas o que não pode ser inferido:

- method/path;
- response records path;
- paginação declarativa simples;
- identity field(s);
- optional static rate limit.

## Defaults e Interceptors

Ordem previsível:

```text
Connector defaults
    ↓
Operation overrides
    ↓
Package Interceptors
    ↓
Transport
```

## Source Identity

- Operation conhecida define identidade internamente.
- Generic/custom Operation pode usar `identity: "id"` ou lista de fields no manifest.
- Sem função Elixir customizada de identity inicialmente.
