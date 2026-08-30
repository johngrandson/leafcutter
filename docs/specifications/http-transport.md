# HTTP Transport

- Estado: MATERIALIZADO
- Decisão: `docs/decisions/ADR-0022-transport-http-e-sequencia-26c.md`

## Objetivo

Definir uma boundary HTTP síncrona, bounded e segura para Operations executáveis. O Transport
conhece protocolo, conexão e buffering; a Operation conhece autenticação, formato, paginação,
status e semântica do vendor.

Este contract cobre somente o incremento 26C1. Package Manifest/module resolution e a primeira
Operation de produto pertencem a 26C2/26C3.

## Ownership

~~~text
leafcutter_connectors
└── LeafcutterConnectors.Transport.HTTP
    ├── Adapter
    ├── Request
    ├── Response
    ├── Error
    └── Finch
~~~

Não existe dependency para `leafcutter_core`, Catalog, Repo ou runtime. Não existe behaviour
genérico `Transport` neste primeiro incremento.

## Implementação e evidência

O contract está materializado em `apps/leafcutter_connectors`. A application supervisiona
somente a instância Finch nomeada; a facade e os valores permanecem livres de Core, Catalog,
Repo e runtime. A dependency e os limites centrais estão em `mix.exs`/`mix.lock` e config.

A prova executável inclui testes puros de Request/Response/adapter contract e testes de rede com
`test/support/http_server.ex`. O servidor TCP local verifica status, chunks, trailers, body cap,
timeouts, uma única tentativa, compartilhamento de pool por origin e ausência de segredos em
logs sem internet ou credenciais reais.

## API pública

~~~elixir
@spec HTTP.request(HTTP.Request.t()) ::
        {:ok, HTTP.Response.t()} | {:error, HTTP.Error.t()}

@spec HTTP.request(HTTP.Request.t(), module()) ::
        {:ok, HTTP.Response.t()} | {:error, HTTP.Error.t()}
~~~

`request/1` usa o adapter Finch ratificado. `request/2` aceita uma dependency de código que
implemente `HTTP.Adapter`; o módulo nunca é derivado de input persistido ou externo.

~~~elixir
defmodule LeafcutterConnectors.Transport.HTTP.Adapter do
  alias LeafcutterConnectors.Transport.HTTP

  @callback request(HTTP.Request.t()) ::
              {:ok, HTTP.Response.t()}
              | {:error, HTTP.Error.t()}
end
~~~

Cada chamada representa uma tentativa. O retorno integral deve ser validável por predicado
puro; adapter output malformado é contract violation.

## Request

Módulo:

~~~text
LeafcutterConnectors.Transport.HTTP.Request
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `method` | `method()` | obrigatório e pertencente à allowlist |
| `url` | `String.t()` | absoluta, UTF-8, `http`/`https`, host presente |
| `headers` | `[header()]` | ordenados, duplicatas preservadas |
| `body` | `binary()` ou `nil` | raw, sem codec implícito |
| `pool_timeout_ms` | `pos_integer()` | finito |
| `receive_timeout_ms` | `pos_integer()` | finito entre chunks |
| `request_timeout_ms` | `pos_integer()` | finito para a tentativa HTTP/1 |
| `max_response_body_bytes` | `pos_integer()` | cap obrigatório do body acumulado |

~~~elixir
@type method :: :get | :head | :post | :put | :patch | :delete | :options
@type header :: {binary(), binary()}
~~~

### URL

- scheme é exatamente `http` ou `https`;
- host não é vazio;
- userinfo e fragment são rejeitados;
- path e query são permitidos;
- credential em URL/query está proibida no primeiro caminho;
- `Inspect` não exibe path nem query.

### Headers

- nomes são tokens HTTP ASCII em lowercase;
- values são binaries;
- nome ou value com CR, LF ou NUL é inválido;
- ordem e duplicatas são preservadas;
- a boundary não combina `set-cookie`, `authorization` ou headers repetidos;
- `Inspect` redige todos os headers.

### Body e limits

Body é raw binary ou `nil`. JSON, form encoding, compression e vendor codecs pertencem à
Operation. `max_response_body_bytes` é sempre explícito; não existe modo `:infinity`.

Os três timeouts são positivos e explícitos. Connect timeout pertence ao pool config porque a
conexão pode ser reutilizada entre requests.

O `request_timeout_ms` é passado ao timeout best-effort de HTTP/1 do Finch. O caller não o
interpreta como deadline preciso nem como prova de que nenhum efeito externo ocorreu.

## Response

Módulo:

~~~text
LeafcutterConnectors.Transport.HTTP.Response
~~~

| Campo | Tipo | Regra |
|---|---|---|
| `status` | `100..599` | status HTTP final |
| `headers` | `[header()]` | ordered, lowercase, duplicatas preservadas |
| `body` | `binary()` | nunca parcial |
| `trailers` | `[header()]` | ordered, lowercase, default vazio |

O adapter usa streaming internamente. Se o `content-length` conhecido ou os chunks recebidos
ultrapassarem o limit, a chamada termina com `:response_too_large`; nenhum Response parcial
cruza a boundary.

Qualquer status bem-formado é success do Transport:

~~~text
HTTP 204 → {:ok, Response}
HTTP 302 → {:ok, Response}
HTTP 401 → {:ok, Response}
HTTP 429 → {:ok, Response}
HTTP 503 → {:ok, Response}
~~~

A Operation decide o significado.

`Inspect` exibe status, header/trailer counts e body byte size. Conteúdo permanece redigido.

## Error

Módulo:

~~~text
LeafcutterConnectors.Transport.HTTP.Error
~~~

Struct:

~~~elixir
%HTTP.Error{reason: reason()}
~~~

Reasons permitidos:

| Reason | Origem |
|---|---|
| `:invalid_request` | Request falhou validação antes da rede |
| `:pool_timeout` | checkout excedeu o limite |
| `:timeout` | connect, receive ou request timeout |
| `:dns` | resolução de host falhou |
| `:connection` | conexão recusada, fechada ou resetada |
| `:tls` | negociação/certificado TLS falhou |
| `:protocol` | resposta HTTP inválida ou incompatível |
| `:response_too_large` | body excedeu o cap explícito |
| `:transport_failure` | erro reconhecido do client sem classificação mais específica |

O error não possui message, metadata ou raw reason. Seu `Inspect` é seguro por construção.

Expected client errors e a exception esperada de pool checkout são normalizados. Exceptions e
exits inesperados não são capturados como `:transport_failure`; eles permanecem defeitos
visíveis da implementação.

## Relação com Operation.Error

Transport não cria `Operation.Error`. A Operation traduz a boundary:

~~~text
connect/receive/request timeout
→ usually Operation.Error(category: :timeout)

pool timeout or connection unavailability
→ usually Operation.Error(category: :temporary)

HTTP status + headers + decoded vendor body
→ Operation-specific classification
~~~

Regras obrigatórias para a futura referência:

- 3xx não é seguido automaticamente;
- 4xx/5xx não é convertido automaticamente pelo Transport;
- rate limit usa header/vendor semantics e `retry_after_ms` bounded;
- vendor code vira code estável controlado pela Operation;
- raw header/body/message nunca entra no error normalizado;
- timeout de Write preserva resultado externo desconhecido e at-least-once.

A matriz exata de status/vendor error será ratificada junto da Operation 26C3, não antes da
escolha do sistema externo.

## Finch adapter

Dependency inicial:

~~~elixir
{:finch, "~> 0.23.0"}
~~~

`LeafcutterConnectors.Application` supervisiona uma instância nomeada do Finch. O default pool
é HTTP/1, `count: 1`, iniciado sob demanda por origin e possui size, connect timeout e
`pool_max_idle_time` finitos. Esses parâmetros vêm de config central com defaults testados;
eles não fazem parte de `Operation.Invocation.config`.

A config central também define um hard maximum finito de response body. O adapter usa o menor
valor entre esse maximum e `Request.max_response_body_bytes`; uma Operation pode apertar o
limite, mas não ampliá-lo.

O cap mede o body raw recebido do client. Qualquer decompression/decoding posterior pertence à
Operation e exigirá limites próprios no primeiro path que o utilizar.

Não criar pool por tenant, Environment, Run, Connection, credential ou Operation. Requests ao
mesmo `{scheme, host, port}` compartilham o pool.

O adapter:

1. recebe somente Request válida;
2. constrói uma request Finch raw;
3. chama `stream_while/5` com pool/receive/request timeouts;
4. acumula status, headers, body e trailers;
5. interrompe ao exceder o body limit;
6. normaliza somente erros esperados;
7. devolve Response validada.

Semânticas proibidas:

- retry automático;
- redirect automático;
- HTTP/2 no primeiro adapter;
- cookie jar;
- JSON/form codec;
- auto decompression;
- response cache;
- public streaming callback.

## Inspect e telemetria

Provas de redaction:

- `inspect(request)` não contém path, query, headers ou body;
- `inspect(response)` não contém headers, trailers ou body;
- errors não carregam raw values;
- test credentials não aparecem em capture log nem em eventos Leafcutter.

Finch emite eventos com `%Finch.Request{}` e response headers na metadata. Handlers Leafcutter
não podem serializar esses campos. Qualquer evento próprio do Transport usa allowlist de
method, scheme, host, status, reason e duração, sem copiar metadata bruta.

## Matriz de testes materializada

### Request

- cada method permitido;
- rejeição de method desconhecido;
- URL HTTP/HTTPS válida;
- rejeição de scheme, host ausente, userinfo e fragment;
- query permitida e redigida;
- headers repetidos preservados;
- rejeição de header name inválido e CR/LF/NUL;
- body `nil` e binary;
- rejeição de timeout/limit zero, negativo, infinity ou tipo inválido.

### Response

- 2xx, 3xx, 4xx e 5xx retornam Response;
- headers repetidos e trailers preservados;
- body vazio e body em múltiplos chunks;
- content-length acima do cap;
- chunk que cruza o cap;
- nenhum body parcial após overflow.

### Falhas

- pool timeout e timeout de connect/receive/request normalizados;
- DNS, connection, TLS e protocol errors sanitizados;
- adapter fake válido;
- retorno malformado de adapter rejeitado;
- exception inesperada permanece visível como defect.

### Semântica de tentativa

- redirect não é seguido;
- resposta retryable não causa segunda request;
- teste local observa exatamente uma tentativa;
- HTTP/1 é a única protocol config;
- pools são compartilhados por origin e não criados por credential.

### Segurança

- Request/Response Inspect redigido;
- query, authorization header, request body e response body ausentes de logs;
- nenhum error contém exception/raw client reason;
- eventos Leafcutter usam somente campos allowlisted.

Os testes de rede usam servidor local determinístico. Não dependem de internet, vendor ou
credenciais reais.

## Fora de escopo

- Package Manifest e build;
- operation registry/resolver;
- primeira Connector/Operation real;
- status/vendor mapping concreto;
- query-string auth;
- request payload/batch limits gerais;
- proxy, HTTP/2, streaming público e upload streaming;
- persisted retry/error policy;
- RunCoordinator, Broadway e durable fan-out;
- Database, SFTP e outros transports.
