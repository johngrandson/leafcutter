# ADR-0021 — Contrato executável de Operation

- Status: Accepted
- Estado de implementação: MATERIALIZADO

## Contexto

O Catalog já publica `ConnectorVersion` e suas `Operation` metadata de forma atômica e
imutável. Cada Operation possui `ref` e `role: source | destination`, mas ainda não existe
contrato executável em `leafcutter_connectors`.

O próximo passo precisa fixar a boundary que o runtime chamará sem antecipar Transport HTTP,
Package Manifest, resolução de módulos, processos Broadway ou persistência de Record/Delivery.
A boundary também precisa manter `leafcutter_connectors` independente de `leafcutter_core`.

## Decisão

### Ownership e dependências

Os behaviours, tipos e structs executáveis pertencem à application
`leafcutter_connectors`, sob o namespace `LeafcutterConnectors.Operation`.

O runtime futuro dependerá simultaneamente de `leafcutter_core` e
`leafcutter_connectors`: ele resolverá ContractVersion pelo Core e chamará a Operation pela
boundary de Connectors. `leafcutter_connectors` não chamará Catalog, Contracts, Repo ou
internals de Run.

O Slice 26B não cria behaviour de Connector. Também não decide como um `operation_id`
persistido encontra um módulo executável; Package Manifest, build e module resolution
continuam separados.

### Behaviours

Uma Operation source implementa:

~~~elixir
@behaviour LeafcutterConnectors.Operation.Read

@callback read(Read.Invocation.t()) ::
            {:ok, Read.Result.t()}
            | {:error, Operation.Error.t()}
~~~

Uma Operation destination implementa:

~~~elixir
@behaviour LeafcutterConnectors.Operation.Write

@callback write(Write.Invocation.t()) ::
            {:ok, Write.Result.t()}
            | {:error, Operation.Error.t()}
~~~

Os callbacks são síncronos. Não existe callback de lifecycle, processo por Operation,
estado persistente ou callback de Transport neste slice. Falhas esperadas retornam o contrato
tipado; exceptions, exits e resultados malformados são defeitos da implementação.

### Valores compartilhados

Payloads, config, metadata, cursores e destination identities que cruzam a boundary são
valores JSON-compatible. Object keys já chegam como strings UTF-8.

`credentials` é um map opaco, efêmero e resolvido pelo caller. Ele nunca é persistido,
serializado ou incluído em logs. O `Inspect` das invocation structs precisa redigir esse
campo.

A config entregue à Operation já é específica da execução e não expõe se um valor veio de
Connection config, promotable config ou local config.

### Read Operation

`Read.Invocation` contém:

- `config`: JSON object não sensível;
- `credentials`: map opaco e efêmero;
- `cursor`: `nil` na primeira chamada ou cursor opaco retornado anteriormente.

`Read.Result` contém:

- `records`: uma página ordenada de payloads JSON-compatible;
- `next_cursor`: cursor JSON-compatible não nulo, ou `nil` quando a leitura terminou;
- `metadata`: JSON object seguro e não autoritativo.

Não existe `done?`: `next_cursor: nil` é a única representação de conclusão. Um cursor
não nulo representa a posição depois da página retornada, precisa avançar em relação ao cursor
de entrada e é persistível/replayable sem interpretação pelo runtime.

Uma página vazia é válida. Se ainda houver progresso, ela traz um novo `next_cursor`; se a
leitura terminou, traz `nil`. Metadata nunca controla paginação ou checkpoint.

O caller persiste o cursor seguinte apenas junto com o fan-out durável da página. Um crash
antes desse commit repete o cursor anterior conforme a semântica at-least-once.

### Write Operation

`Write.Invocation` contém:

- `config`: JSON object não sensível;
- `credentials`: map opaco e efêmero;
- `items`: batch não vazio e ordenado de `Write.Item`.

Cada item possui:

- `ref`: token opaco, único no batch, fornecido pelo caller;
- `payload`: valor JSON-compatible já transformado e validado.

`Write.Result` contém uma lista `results`. Ela precisa possuir exatamente um
`Write.ItemResult` por item de entrada, na mesma ordem e com o mesmo `ref`.

Cada item result contém:

~~~elixir
{:ok, destination_identity}
| {:error, %LeafcutterConnectors.Operation.Error{}}
~~~

Um result com successes e errors é o partial success normal. `{:ok, Write.Result.t()}`
significa que a Operation produziu uma classificação completa e confiável para o batch, não
que todos os items tiveram sucesso.

`{:error, Operation.Error.t()}` no callback inteiro é reservado para situações em que não
existe um conjunto completo e confiável de resultados por item. Em uma falha retryable de
batch, o caller assume que efeitos externos podem ter acontecido e preserva at-least-once.

### Erro normalizado

`LeafcutterConnectors.Operation.Error` possui:

- `category`: `:validation | :authentication | :rate_limited | :timeout | :temporary |
  :permanent`;
- `code`: string estável, não vazia e controlada pela implementação;
- `message`: string segura opcional;
- `retry_after_ms`: hint não negativo opcional para `:rate_limited` ou `:temporary`;
- `metadata`: JSON object seguro, vazio por padrão.

Não existe campo `retryable`; a política deriva de `category`:

| Categoria | Tratamento ratificado |
|---|---|
| `validation` | sem retry automático |
| `authentication` | sem retry temporizado; exige recuperação explícita de configuração/credencial |
| `rate_limited` | retry posterior, respeitando o hint quando presente |
| `timeout` | retry; o efeito externo pode ser desconhecido |
| `temporary` | retry posterior |
| `permanent` | sem retry automático |

`code`, `message` e `metadata` nunca carregam credentials, config, payload, body,
headers, stacktrace ou valores externos não sanitizados. A representação persistida futura de
Attempt/Delivery, backoff e max attempts não fazem parte deste ADR.

### Pontos de validação de payload

A validação source ocorre depois do retorno da Read Operation e antes de identidade, hash,
Record, Delivery ou checkpoint:

~~~text
Read.read/1
→ source Contracts.validate/2
→ future durable source processing
~~~

A validação destination ocorre depois da Transformation e antes de criar o `Write.Item`:

~~~text
Transformation
→ destination Contracts.validate/2
→ Write.write/1
~~~

A Operation não chama `Contracts.validate/2`. Um erro JSV local não é convertido em
chamada externa. Uma rejeição semântica do sistema externo ainda pode retornar
`:validation` mesmo depois da validação JSON Schema local.

## Estado materializado

`leafcutter_connectors` contém os tipos JSON compartilhados, `Operation.Error`, os
behaviours Read/Write e todos os invocation/result values ratificados. As invocation structs
redigem credentials por `Inspect`.

As invariantes são verificáveis por predicados puros:

- `Operation.json_value?/1`, `json_object?/1` e `cursor?/1`;
- `valid?/1` nos values;
- `Read.Result.valid_for?/2` para avanço de cursor;
- `Write.Result.valid_for?/2` para completude, ordem e correlação;
- `Read.valid_return?/2` e `Write.valid_return?/2` para o retorno integral do callback.

A materialização de 26B não iniciou supervisor nem adicionou dependency de Core, Ecto, Repo,
HTTP ou runtime. Os módulos de Operation permanecem process-free e independentes de Transport;
o supervisor Finch introduzido posteriormente pertence exclusivamente ao ADR-0022.

## Consequências

- paginação de page, offset, cursor ou next URL fica encapsulada em um cursor durável opaco;
- a ausência de `done?` elimina dois campos capazes de representar estados contraditórios;
- results completos, ordenados e correlacionados por `ref` tornam partial success
  determinístico;
- o erro de Operation é in-memory e não antecipa o schema persistido de Attempt/Delivery;
- credentials permanecem fora de RunSnapshot, structs inspecionáveis e errors;
- nenhum GenServer ou dependency nova é necessário para materializar o contrato;
- HTTP foi separado em 26C1; tradução de status/vendor errors dos endpoints reais permanece em 26C3.

## Fora de escopo

- Transport behaviour, request/response e HTTP client/pool;
- module registry, Package Manifest e build de Integration Packages;
- idempotency keys e destination upsert;
- Record, Delivery, Attempt, Checkpoint e persisted error shape;
- backoff, max attempts, jitter e scheduler;
- payload/body/batch limits;
- SourceIdentity e IdentityMapping;
- carregamento pelo RunCoordinator ou Broadway;
- auth provider, OAuth refresh e secret resolution;
- outros transports.

## Provas exigidas na materialização

- behaviours possuem somente os callbacks ratificados;
- invocation/result/error structs preservam os campos e typespecs definidos;
- `Inspect` redige credentials;
- Read aceita primeira chamada, continuação, página vazia e conclusão por `nil`;
- Write prova batch completo, ordem, correlação por `ref` e partial success;
- categories e `retry_after_ms` obedecem a matriz;
- valores duráveis rejeitam termos não JSON e UTF-8 inválido;
- os módulos de Operation não introduzem dependency para Core, processo OTP ou detalhe HTTP.

## Evolução posterior

O ADR-0022 divide o antigo Slice 26C: Transport HTTP pertence a 26C1; o ADR-0023 ratifica
Package Manifest/build binding e module resolution em 26C2; o fluxo real completo, com uma
Read source, uma ou mais Write destinations e tradução vendor-specific por endpoint, pertence
a 26C3. Essa evolução não altera a boundary materializada
por este ADR.
