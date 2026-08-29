# Connectors, Operations e Transports

> **Status: PARCIALMENTE MATERIALIZADO.** Connector, ConnectorVersion e Operation metadata
> existem no Catalog, e a boundary executável do Slice 26B existe em `leafcutter_connectors`.
> Transport e a primeira referência HTTP pertencem ao Slice 26C.

## Estado materializado

~~~text
leafcutter_core
└── Connector
    └── immutable ConnectorVersion
        └── Operation metadata

leafcutter_connectors
└── LeafcutterConnectors.Operation
    ├── Read behaviour + values
    ├── Write behaviour + values
    └── Error
~~~

`Leafcutter.Catalog.Connectors` cria e lê Connector identities e publica ConnectorVersion
com suas Operations atomicamente. `leafcutter_connectors` materializa os behaviours, structs
e predicados puros do contract executável, sem processo próprio.

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

## Slice 26C — Transport e referência HTTP

HTTP permanece o primeiro Transport planejado. O slice deverá ratificar:

- Transport behaviour;
- request/response boundary;
- primeiro Connector/Operation de referência;
- resolução do módulo executável para a referência publicada;
- HTTP client e pool strategy;
- timeout, status, rate-limit e vendor-error translation.

Database, SFTP e outros transports só entram com demanda real.

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
- `docs/specifications/operation-contract.md`
- `docs/specifications/error-retry-model.md`
