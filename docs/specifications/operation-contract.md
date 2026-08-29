# Operation contract

- Estado: MATERIALIZADO
- Decisão: `docs/decisions/ADR-0021-operation-executavel.md`

## Objetivo

Definir a boundary executável, síncrona e independente de Transport para Operations source e
destination. Operation metadata continua owned pelo Catalog; behaviours e valores de execução
pertencem a `leafcutter_connectors`.

## Limite entre applications

~~~text
leafcutter_core
→ Catalog Operation metadata
→ Contracts.compile/1 and validate/2

leafcutter_connectors
→ executable Operation behaviours and values

leafcutter_runtime
→ future caller that composes both boundaries
~~~

`leafcutter_connectors` não depende de `leafcutter_core`. Nenhum struct desta
specification recebe Organization, Environment, Integration, Deployment, Run, ContractVersion,
Connection ou SecretVersion.

A resolução de `operation_id` para módulo, Package Manifest e build permanecem fora deste
contract.

## Tipos compartilhados

O namespace raiz `LeafcutterConnectors.Operation` define:

~~~elixir
@type json_object :: %{optional(String.t()) => json_value()}

@type json_value ::
        nil
        | boolean()
        | number()
        | String.t()
        | [json_value()]
        | json_object()

@type cursor ::
        boolean()
        | number()
        | String.t()
        | [json_value()]
        | json_object()

@type destination_identity :: json_value()
~~~

Regras:

- strings e object keys são UTF-8 válidos;
- object keys são strings, não atoms;
- structs, tuples, PIDs, references, functions e improper lists não são valores JSON;
- `cursor` exclui `nil`; `nil` é reservado para início/conclusão;
- cursores e destination identities são opacos para o runtime;
- nenhum valor durável contém credentials ou material de autenticação.

## Error

Módulo:

~~~text
LeafcutterConnectors.Operation.Error
~~~

Struct:

| Campo | Tipo | Regra |
|---|---|---|
| `category` | `category()` | obrigatório |
| `code` | `String.t()` | obrigatório, não vazio, UTF-8 e estável |
| `message` | `String.t()` ou `nil` | opcional, UTF-8 e sanitizado |
| `retry_after_ms` | `non_neg_integer()` ou `nil` | somente rate-limited/temporary |
| `metadata` | `Operation.json_object()` | seguro e vazio por padrão |

~~~elixir
@type category ::
        :validation
        | :authentication
        | :rate_limited
        | :timeout
        | :temporary
        | :permanent
~~~

O erro é uma representação in-memory. Ele não é o schema persistido futuro de Attempt ou
Delivery.

### Política por categoria

| Categoria | Retry automático | Observação |
|---|---|---|
| `validation` | não | invocation/config ou rejeição semântica |
| `authentication` | não temporizado | requer recuperação explícita; a Run permanece pinada |
| `rate_limited` | sim | `retry_after_ms` é hint quando presente |
| `timeout` | sim | resultado externo pode ser desconhecido |
| `temporary` | sim | indisponibilidade recuperável |
| `permanent` | não | operação não terá sucesso sem mudança de definição |

Não adicionar `retryable` ao struct. Não carregar payload, config, credentials, raw
request/response, headers, stacktrace ou vendor message não sanitizada em nenhum campo.

## Read Operation

### Behaviour

~~~elixir
defmodule LeafcutterConnectors.Operation.Read do
  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Operation.Read.{Invocation, Result}

  @callback read(Invocation.t()) ::
              {:ok, Result.t()}
              | {:error, Operation.Error.t()}
end
~~~

### Invocation

Módulo:

~~~text
LeafcutterConnectors.Operation.Read.Invocation
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `config` | `Operation.json_object()` | obrigatório e não sensível |
| `credentials` | `map()` | obrigatório, opaco, efêmero e redigido por Inspect |
| `cursor` | `Operation.cursor()` ou `nil` | `nil` na primeira chamada |

A config já chega resolvida para a Operation. A struct não revela a origem de seus valores.
`credentials` usa `%{}` quando a Operation não exige autenticação.

### Result

Módulo:

~~~text
LeafcutterConnectors.Operation.Read.Result
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `records` | `[Operation.json_value()]` | página ordenada; pode ser vazia |
| `next_cursor` | `Operation.cursor()` ou `nil` | `nil` encerra a leitura |
| `metadata` | `Operation.json_object()` | seguro, não autoritativo, default `%{}` |

Invariantes:

1. o callback retorna no máximo uma página lógica;
2. a ordem de `records` é a ordem observada na source;
3. `next_cursor: nil` é a única indicação de conclusão;
4. um `next_cursor` não nulo representa a posição depois da página;
5. um `next_cursor` não nulo difere do cursor de entrada;
6. página vazia com novo cursor é válida;
7. metadata não participa de paginação, checkpoint, retry ou correctness;
8. o runtime devolve o cursor opaco sem reescrever sua representação.

### Checkpoint

~~~text
input cursor
→ Read.read/1
→ records + next_cursor
→ source validation
→ future Record + Deliveries + Checkpoint transaction
~~~

O checkpoint só recebe `next_cursor` quando a página e seu fan-out commitam. Crash anterior
repete o input cursor. Esta specification não define o schema de Checkpoint.

## Write Operation

### Behaviour

~~~elixir
defmodule LeafcutterConnectors.Operation.Write do
  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Operation.Write.{Invocation, Result}

  @callback write(Invocation.t()) ::
              {:ok, Result.t()}
              | {:error, Operation.Error.t()}
end
~~~

### Item

Módulo:

~~~text
LeafcutterConnectors.Operation.Write.Item
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `ref` | `String.t()` | obrigatório, não vazio, UTF-8, único no batch |
| `payload` | `Operation.json_value()` | já transformado e validado |

`ref` é um token opaco do caller. A Operation o usa somente para correlacionar o resultado e
não infere Delivery, Run ou identidade de domínio.

### Invocation

Módulo:

~~~text
LeafcutterConnectors.Operation.Write.Invocation
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `config` | `Operation.json_object()` | obrigatório e não sensível |
| `credentials` | `map()` | obrigatório, opaco, efêmero e redigido por Inspect |
| `items` | `nonempty_list(Write.Item.t())` | batch não vazio, ordenado, refs únicas |

### ItemResult

Módulo:

~~~text
LeafcutterConnectors.Operation.Write.ItemResult
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `ref` | `String.t()` | cópia exata do input ref correspondente |
| `outcome` | `outcome()` | success ou error normalizado |

~~~elixir
@type outcome ::
        {:ok, Operation.destination_identity()}
        | {:error, Operation.Error.t()}
~~~

Uma destination identity é opaca, JSON-compatible e nunca contém credential.

### Result

Módulo:

~~~text
LeafcutterConnectors.Operation.Write.Result
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `results` | `nonempty_list(Write.ItemResult.t())` | completo e na ordem do batch |

Para uma invocation com `items = [a, b, c]`, o result válido possui exatamente:

~~~text
results = [result(a), result(b), result(c)]
~~~

Cada posição repete o mesmo `ref`. Resultado ausente, extra, duplicado, fora de ordem ou com
ref diferente é violação do contract.

Mixed outcomes representam partial success:

~~~elixir
%Write.Result{
  results: [
    %Write.ItemResult{ref: "a", outcome: {:ok, "external-1"}},
    %Write.ItemResult{
      ref: "b",
      outcome: {:error, %Operation.Error{category: :validation, code: "rejected"}}
    },
    %Write.ItemResult{ref: "c", outcome: {:ok, nil}}
  ]
}
~~~

`{:ok, Write.Result.t()}` significa classificação completa, mesmo quando todos os outcomes
são errors.

O callback retorna `{:error, Operation.Error.t()}` somente quando não consegue produzir um
conjunto completo e confiável. Para timeout/temporary/rate-limited no batch inteiro, o runtime
não presume ausência de efeitos externos.

## Validação de payload

### Source

~~~text
Read.Result.records
→ Leafcutter.Catalog.Contracts.validate(source_contract_version_id, payload)
→ future SourceIdentity/PayloadHash/Record/Delivery/Checkpoint
~~~

A validação acontece antes de qualquer payload ser tratado como record confiável ou de o
checkpoint avançar.

### Destination

~~~text
Transformation output
→ Leafcutter.Catalog.Contracts.validate(destination_contract_version_id, payload)
→ Write.Item
→ Write.write/1
~~~

Uma falha local de ContractVersion impede a chamada externa. Uma rejeição de negócio/vendor
depois dessa validação usa `Operation.Error{category: :validation}`.

O caller em `leafcutter_runtime` compõe as APIs. O behaviour e sua implementação não chamam
Catalog ou Contracts.

## Config e credentials

- `config` contém somente valores não sensíveis necessários pela Operation;
- `credentials` é resolvido imediatamente antes da invocation;
- invocation structs redigem `credentials` em `Inspect`;
- credentials não entram em result, error, metadata, cursor ou destination identity;
- este contract não define provider, OAuth refresh, encryption ou rotation.

## Falhas e at-least-once

- erros esperados usam `Operation.Error`;
- exceptions/exits representam defeito ou falha não normalizada da implementação;
- resultado com shape/invariantes inválidos é contract violation, não `:permanent`;
- retry de read pode repetir uma página;
- retry de write pode repetir efeito externo;
- idempotency/upsert podem reduzir duplicação posteriormente, sem promessa exactly-once.

## API de validação materializada

A materialização expõe predicados booleanos e não cria um segundo error contract para
construção:

- `Operation.json_value?/1`, `json_object?/1` e `cursor?/1`;
- `valid?/1` em Error, invocations, results, Item e ItemResult;
- `Read.Result.valid_for?/2` confronta `next_cursor` com a invocation;
- `Write.Result.valid_for?/2` confronta results com o batch da invocation;
- `Read.valid_return?/2` e `Write.valid_return?/2` validam o retorno completo.

Os predicados não executam I/O, não resolvem módulo e não chamam Catalog ou Contracts.

## Matriz de testes da materialização

### Tipos e segurança

- JSON scalars, lists e objects válidos;
- rejeição de atom key, struct, tuple, PID, function, improper list e UTF-8 inválido;
- invocation `Inspect` nunca contém credentials;
- error rejeita code vazio e metadata não JSON;
- `retry_after_ms` somente nas categories permitidas.

### Read

- primeira invocation com cursor `nil`;
- página normal e continuação opaca;
- página vazia com progresso;
- conclusão por `next_cursor: nil`;
- rejeição de cursor não JSON, nulo como continuação e cursor sem progresso;
- metadata não altera o cursor.

### Write

- batch não vazio e refs únicas;
- payloads JSON-compatible;
- resultado completo na mesma ordem;
- destination identity opcional;
- partial success misto;
- todos os items em error ainda retornam `{:ok, result}`;
- top-level error quando não há classificação completa;
- rejeição de result ausente, extra, duplicado, reordenado ou com ref divergente.

### Boundary

- fake Read e Write modules satisfazem os behaviours;
- nenhum módulo depende de Core, Ecto, Repo, HTTP ou processo OTP;
- os pontos source/destination permanecem fora das implementations.

## Fora de escopo

- Transport/HTTP;
- module resolution e Package Manifest;
- persisted error envelope;
- Delivery statuses, backoff, max attempts e jitter;
- idempotency key;
- payload/body/batch limits;
- SourceIdentity/IdentityMapping;
- Broadway e RunCoordinator;
- secret provider/OAuth;
- outros transports.
