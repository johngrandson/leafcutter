# Connectors, Operations e Transports

> **Status: PARCIALMENTE MATERIALIZADO.** Connector/Operation metadata, a boundary executável
> de Operation e o Transport HTTP 26C1 existem. Package Manifest/module resolution (26C2) e
> a primeira referência real (26C3) estão abertos.

## Estado materializado

~~~text
leafcutter_core
└── Connector
    └── immutable ConnectorVersion
        └── Operation metadata

leafcutter_connectors
├── LeafcutterConnectors.Operation
│   ├── Read behaviour + values
│   ├── Write behaviour + values
│   └── Error
└── LeafcutterConnectors.Transport.HTTP
    ├── Adapter + Request/Response/Error
    └── supervised Finch HTTP/1 adapter
~~~

`Leafcutter.Catalog.Connectors` cria e lê Connector identities e publica ConnectorVersion
com suas Operations atomicamente. `leafcutter_connectors` materializa os behaviours, structs
e predicados puros de Operation. Essa boundary permanece process-free; a application
supervisiona somente a instância Finch necessária ao Transport HTTP.

## Separação

~~~text
Connector
→ conhece o sistema externo

Operation
→ conhece uma ação específica

Transport
→ conhece o protocolo
~~~

Catalog possui metadata e versões. `leafcutter_connectors` possui a boundary executável
sem depender de Catalog ou Repo. O runtime futuro comporá as duas applications.

ContractVersion + JSON Schema/JSV é uma boundary anterior e separada, owned pelo Catalog. A
Operation não compila nem valida ContractVersion.

## Slice 26B — contract materializado

Owner:

~~~text
leafcutter_connectors
└── LeafcutterConnectors.Operation
    ├── Error
    ├── Read
    │   ├── Invocation
    │   └── Result
    └── Write
        ├── Invocation
        ├── Item
        ├── ItemResult
        └── Result
~~~

Callbacks:

~~~elixir
Read.read(Read.Invocation.t())
→ {:ok, Read.Result.t()} | {:error, Operation.Error.t()}

Write.write(Write.Invocation.t())
→ {:ok, Write.Result.t()} | {:error, Operation.Error.t()}
~~~

Os callbacks são síncronos. Não existe processo por Operation, lifecycle callback, Transport
callback ou dependency para `leafcutter_core`. Predicados `valid?/1`, `valid_for?/2` e
`valid_return?/2` materializam as invariantes sem criar um novo error shape de construção.

### Read

~~~text
resolved config + ephemeral credentials + opaque cursor
→ one ordered page
→ records + next_cursor + safe metadata
~~~

`nil` como input inicia a leitura. `next_cursor: nil` encerra a leitura; não existe
`done?`. Cursores não nulos são JSON-compatible, persistíveis, opacos e precisam representar
progresso. Page, offset, vendor cursor e next URL ficam escondidos nessa representação.

### Write

~~~text
ordered validated items with unique refs
→ complete ordered item results
→ success or normalized error per ref
~~~

Cada result repete o input `ref`, preserva ordem e cobre exatamente um item. Misturar
successes e errors é o partial success normal. Um erro no callback inteiro significa que a
Operation não conseguiu produzir uma classificação completa e confiável para o batch.

### Config e credentials

Config chega como JSON object não sensível já resolvido para a Operation. Credentials chegam
em map opaco e efêmero, são redigidas por `Inspect` e nunca entram em cursor, result, error,
metadata ou persistência.

A boundary não expõe Organization, Integration, Deployment, Run, Connection, SecretVersion ou
a origem de cada valor resolvido.

## Validação de Contracts

Source:

~~~text
Read.read/1
→ Contracts.validate(source_contract_version_id, payload)
→ future durable source processing
~~~

Destination:

~~~text
Transformation
→ Contracts.validate(destination_contract_version_id, payload)
→ Write.write/1
~~~

A validação pertence ao caller em `leafcutter_runtime`, que pode usar Core e Connectors. A
Operation não chama `Contracts.validate/2`.

## Error taxonomy materializada na boundary

| Categoria | Política |
|---|---|
| `validation` | sem retry automático |
| `authentication` | recuperação explícita, sem retry temporizado |
| `rate_limited` | retry posterior |
| `timeout` | retry, com efeito externo possivelmente desconhecido |
| `temporary` | retry posterior |
| `permanent` | sem retry automático |

`Operation.Error` contém category, code estável, message segura opcional,
`retry_after_ms` limitado e metadata JSON segura. Não contém `retryable`: a policy deriva
da category. O schema persistido de Attempt/Delivery continua posterior.

## Slice 26C — sequência dividida

O ADR-0022 corrige a dependência entre Transport, packages e uma referência de produto:

~~~text
26C1 HTTP Transport boundary + Finch adapter (materializado)
→ 26C2 Package Manifest/build binding + module resolution (aberto)
→ 26C3 first production reference Operation (aberto)
~~~

### 26C1 — Transport HTTP

Owner:

~~~text
leafcutter_connectors
└── LeafcutterConnectors.Transport.HTTP
    ├── Adapter
    ├── Request
    ├── Response
    ├── Error
    └── Finch
~~~

A facade síncrona executa exatamente uma tentativa e aceita Request com method, URL, headers,
raw body, três timeouts finitos e response body limit obrigatório. Response preserva status,
headers, body e trailers; 3xx, 4xx e 5xx não são errors de Transport.

O adapter Finch usa HTTP/1, pool nomeado supervisionado, uma shard por origin e origins
iniciados sob demanda. Size, connect timeout, idle timeout e hard response-body maximum são
finitos e centrais. Não existe pool por Run, tenant, Connection, credential ou Operation.

Redirect, retry, cookie jar, JSON codec, auto decompression, HTTP/2 e streaming público não
fazem parte do primeiro adapter. Streaming interno existe somente para interromper bodies
acima do cap sem devolver resposta parcial.

`HTTP.Error` normaliza invalid request, pool timeout, timeout, DNS, connection, TLS, protocol,
response-too-large e client failures reconhecidos sem carregar raw reason. A Operation
traduz isso para `Operation.Error`.

Request e Response redigem path, query, headers e body em Inspect. Handlers Leafcutter não
serializam a metadata bruta dos eventos Finch; qualquer evento próprio usa campos allowlisted.
A implementação e os testes locais determinísticos estão materializados em
`apps/leafcutter_connectors`.

### 26C2 — executable package binding

A resolução não será antecipada por application config, filesystem discovery, nome de módulo
livre ou atom criado de valor persistido. Package Manifest/build deverá ligar refs versionadas
a módulos já compilados de forma explícita e auditável. O runtime comporá a binding com APIs
públicas do Catalog; `leafcutter_connectors` não consulta Repo.

### 26C3 — referência de produto

A primeira referência exige selecionar um sistema externo e uma Read ou Write Operation real.
Somente então serão ratificados autenticação, paginação ou batch, status mapping,
`Retry-After`, vendor error decoding e codes sanitizados. Um servidor local de teste não conta
como Connector/Operation publicada.

## Restrições

- não criar GenServer por Connector/Operation sem lifecycle real;
- não esconder Transformation dentro da Operation;
- não persistir ou inspecionar credentials;
- não acoplar runtime genérico a detalhes de HTTP;
- não colocar Catalog/Repo dentro de `leafcutter_connectors`;
- não introduzir Connector behaviour sem uma necessidade além de Operation;
- não implementar múltiplos transports por antecipação.

## Referências

- `docs/decisions/ADR-0008-connector-operation-transport.md`
- `docs/decisions/ADR-0021-operation-executavel.md`
- `docs/decisions/ADR-0022-transport-http-e-sequencia-26c.md`
- `docs/specifications/operation-contract.md`
- `docs/specifications/http-transport.md`
- `docs/specifications/error-retry-model.md`
