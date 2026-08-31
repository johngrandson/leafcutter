# ADR-0022 — Transport HTTP e sequência do Slice 26C

- Status: Accepted
- Estado de implementação: MATERIALIZADO — 26C1
- Data: 2026-08-29
- Materializado em: 2026-08-30

## Contexto

O Slice 26B materializou a boundary síncrona de `Operation` em
`leafcutter_connectors`. O passo seguinte precisa permitir uma chamada HTTP real sem mover
detalhes de protocolo para o runtime e sem expor credentials em logs, errors ou valores
duráveis.

O escopo originalmente agrupado como Slice 26C também incluía a primeira Operation de
referência e a resolução de `operation_id` para módulo executável. Naquele momento, esses dois
itens ainda dependiam de decisões abertas: Package Manifest, inclusão de packages no build e
seleção de um sistema externo real. O `operation_id` persistido é um UUID do Catalog, não uma identidade de
módulo estável. Implementar toda a sequência agora exigiria um registry implícito por config,
filesystem discovery ou nomes de módulo persistidos, canonizando por acidente uma decisão
ainda aberta.

O primeiro transporte também precisa impedir retry, redirect e buffering ilimitado
implícitos. Uma chamada da Operation deve representar uma única tentativa de rede, preservando
a semântica at-least-once para o caller.

## Decisão

### Divisão do Slice 26C

O Slice 26C passa a ser executado em três incrementos ordenados:

~~~text
26C1 HTTP Transport boundary + Finch adapter
→ 26C2 Package Manifest/build executable binding + module resolution
→ 26C3 first production reference Operation
~~~

Este ADR ratificou somente 26C1, agora materializado. Naquele momento, 26C2 ainda precisava
ser ratificado antes de qualquer mapeamento de `operation_id` para módulo. 26C3 exige uma escolha explícita de sistema
externo,
Operation, autenticação, paginação ou escrita e semântica de erros do vendor.

Um servidor HTTP local ou adapter fake usado em testes de conformance não é uma Operation de
referência de produto e não publica metadata no Catalog.

### Ownership e módulos

A boundary pertence a `leafcutter_connectors`, sem dependency para Core, Catalog, Repo ou
runtime:

~~~text
LeafcutterConnectors.Transport.HTTP
├── Adapter
├── Request
├── Response
├── Error
└── Finch
~~~

Não será criado um behaviour genérico comum a protocolos diferentes. O primeiro contract é
HTTP-specific; Database, SFTP e outros transports entram somente quando uma segunda demanda
real revelar uma abstração compartilhada.

`HTTP.request/1` é a facade usada por código de package e delega ao adapter Finch. Uma variante
`HTTP.request/2` pode receber um módulo que implemente `HTTP.Adapter` para composição e teste,
mas esse módulo é uma dependency de código: nunca vem de config, credentials, banco ou input
externo.

O adapter implementa:

~~~elixir
@callback request(Request.t()) ::
            {:ok, Response.t()}
            | {:error, Error.t()}
~~~

O callback é síncrono e representa exatamente uma tentativa de rede.

### Request

`HTTP.Request` contém:

| Campo | Regra |
|---|---|
| `method` | `:get | :head | :post | :put | :patch | :delete | :options` |
| `url` | URL absoluta `http`/`https`, com host e sem userinfo ou fragment |
| `headers` | lista ordenada de pares binários; nomes canônicos lowercase |
| `body` | `binary()` ou `nil` |
| `pool_timeout_ms` | inteiro positivo e finito |
| `receive_timeout_ms` | inteiro positivo e finito entre chunks |
| `request_timeout_ms` | inteiro positivo e finito para a tentativa HTTP/1 |
| `max_response_body_bytes` | inteiro positivo e limite obrigatório de buffering |

Headers preservam ordem e duplicatas. Nomes obedecem ao token HTTP; nomes e values rejeitam
CR, LF e NUL. Query string é permitida, mas o primeiro path não coloca credential na URL.
Autenticação deve usar headers enquanto uma exceção vendor-specific não for ratificada.

`Inspect` mostra somente method, origin e limites seguros. Path, query, headers e body ficam
redigidos.

### Response

`HTTP.Response` contém status, headers, body binário e trailers. Headers e trailers preservam
ordem e duplicatas, com nomes normalizados para lowercase.

O adapter acumula o body por streaming interno e interrompe a request quando
`max_response_body_bytes` for excedido. Ele nunca devolve response parcial. `Inspect` mostra
somente status, contagens e byte size; headers, trailers e body ficam redigidos.

Todo status HTTP bem-formado, inclusive 3xx, 4xx e 5xx, é `{:ok, Response.t()}`. Transport não
decide se um status é success, authentication, rate limit, validation ou falha permanente.

### Erro de Transport

`HTTP.Error` contém somente um reason sanitizado:

~~~text
invalid_request
pool_timeout
timeout
dns
connection
tls
protocol
response_too_large
transport_failure
~~~

Nenhum error carrega URL, path, query, headers, body, credentials, exception, stacktrace ou
raw client/vendor reason. Erros reconhecidos do client e a exception esperada de checkout do
pool são normalizados. Exceptions e exits inesperados continuam sendo defeitos, não falsos
erros de domínio.

A futura Operation traduz Transport errors para `Operation.Error`. `:timeout` normalmente
produz a category homônima; indisponibilidade de conexão/pool normalmente produz
`:temporary`. TLS, protocol e response size exigem contexto da Operation para decidir entre
erro recuperável e permanente.

HTTP status, `Retry-After` e error bodies são responsabilidade da Operation. A Operation usa
status/headers e decodificação vendor-specific para produzir code estável e metadata
allowlisted; raw response material nunca entra em `Operation.Error`.

### Client e pool

O primeiro adapter usa Finch `~> 0.23.0` diretamente, sem Req. `leafcutter_connectors` passa a
ter uma application supervisionada porque o pool HTTP possui lifecycle real.

A application inicia uma instância Finch nomeada. O default pool:

- usa somente HTTP/1;
- possui um pool process por origin (`count: 1`);
- inicia origins sob demanda;
- tem `size`, connect timeout e idle timeout finitos e configurados centralmente;
- aplica um hard maximum central e finito ao response body, além do limit menor pedido pela
  Request;
- é compartilhado por chamadas ao mesmo origin, sem pool por Run, tenant, Connection,
  credential ou Operation.

HTTP/1 evita o retry transparente de draining documentado para requests HTTP/2 do Finch. A
facade não segue redirects, não repete requests, não mantém cookie jar, não codifica/decodifica
JSON e não descomprime body. Cada policy fica explícita na Operation ou em uma decisão futura.

O adapter usa streaming interno para aplicar o body limit e passa os três timeouts finitos ao
client. O `request_timeout` é best-effort conforme o contract do Finch; não é um deadline
preciso do runtime. Pool tuning posterior deriva de métricas e não é parte do contract de uma
Operation.

### Segurança e telemetria

Request, Response e invocation values que podem carregar credenciais possuem `Inspect`
redigido. Leafcutter não registra request/response bodies, headers, path ou query.

Finch publica eventos Telemetry que incluem o request bruto e, em alguns eventos, response
headers. Nenhum handler Leafcutter pode serializar esses campos. Eventos sanitizados do
Transport, se materializados, usam allowlist de method, scheme, host, status, reason e duração;
eles não repassam metadata bruta do Finch.

### Resolução de módulo e referência real

Este ADR proíbe como solução intermediária:

- map de UUID de Catalog para módulo em application config;
- filesystem auto-discovery;
- `String.to_atom/1` ou equivalente sobre valor persistido;
- nome de módulo livre no Catalog;
- fallback por `Operation.ref` sem binding versionado de package.

O ADR-0023 ratifica 26C2 como uma binding explícita e auditável entre
`PackageVersion.manifest_sha256`, refs locais e módulos já compilados no build. O runtime
compõe essa binding com APIs públicas do Catalog; `leafcutter_connectors` não consulta o banco.

Somente depois dessa decisão uma Operation real será publicada como referência em 26C3.

## Alternativas consideradas

### Implementar 26C inteiro antes do Package Manifest

Rejeitada porque criaria um manifest implícito e uma segunda authority para `operation_id`.

### Behaviour genérico de Transport

Rejeitado porque somente HTTP possui requisitos concretos. Uma assinatura comum agora seria
uma abstração especulativa.

### Req como primeiro client

Não escolhido. Req oferece uma API de alto nível, mas sua policy padrão inclui conveniences
como retries e redirects que precisariam ser desativadas. Finch expõe diretamente pooling,
timeouts e streaming necessários ao contract de uma tentativa.

### Pool por tenant, Run ou credential

Rejeitado no primeiro caminho por multiplicar processos e misturar lifecycle de negócio com
conexões HTTP. Isolamento futuro exige evidência operacional.

## Estado atual

O código materializa a facade e o Adapter contract HTTP, Request/Response/Error validados,
Inspect redigido e o adapter Finch HTTP/1. `LeafcutterConnectors.Application` supervisiona uma
instância nomeada com pools por origem iniciados sob demanda. A resposta é acumulada por
`stream_while/5` e interrompida sem retorno parcial ao exceder o menor cap central/por request.
Testes puros e um servidor TCP local determinístico cobrem contrato, uma tentativa, timeouts,
overflow, headers/trailers, compartilhamento por origem e ausência de segredos em logs.

## Futuro preservado

- primeira Operation real e tradução de status/vendor errors;
- request payload/batch limits além do response body cap do Transport;
- proxy, HTTP/2, streaming público, upload streaming e query-string authentication;
- persisted Attempt/Delivery error, backoff, jitter e max attempts;
- data plane, Broadway, durable fan-out e lifecycle de Run;
- outros transports.

## Consequências

- `leafcutter_connectors` possui dependency Finch e um supervisor limitado ao lifecycle do
  pool HTTP;
- uma chamada HTTP fica bounded por timeouts e body limit explícitos;
- redirect e retry não podem ocorrer sem decisão visível da Operation/runtime;
- Transport errors e HTTP responses possuem responsabilidades separadas;
- a primeira execução de produto permanece bloqueada até materializar 26C2 e ratificar/materializar 26C3;
- o checkpoint não finge que module resolution foi resolvida antes do Package Manifest.

## Evolução posterior

O ADR-0023 fecha o contract de 26C2 sem alterar a boundary HTTP. Seus passos 35–38 materializam
Manifest v1 por digest, bindings literais, persistência imutável do digest, inventory/release
e resolução no runtime. A expressão anterior “primeira Operation” tornou-se insuficiente:
a topologia ratificada exige um package completo com exatamente uma Read source e uma ou mais
Write destinations. 26C3 continua separado, e a escolha dos sistemas/endpoints permanece
aberta para ratificação.

## Evidência

- `apps/leafcutter_connectors/lib/leafcutter_connectors/transport/http.ex`
- `apps/leafcutter_connectors/lib/leafcutter_connectors/transport/http/finch.ex`
- `apps/leafcutter_connectors/test/leafcutter_connectors/transport/http/`
- `apps/leafcutter_connectors/test/support/http_server.ex`
- `apps/leafcutter_connectors/mix.exs`, `config/config.exs`, `config/test.exs` e `mix.lock`
- `docs/specifications/http-transport.md`
- `docs/decisions/ADR-0008-connector-operation-transport.md`
- `docs/decisions/ADR-0021-operation-executavel.md`
- `docs/specifications/operation-contract.md`
- `docs/specifications/error-retry-model.md`
- `docs/specifications/package-manifest-v1.md`
- Finch: <https://hexdocs.pm/finch/Finch.html>
- Finch Telemetry: <https://hexdocs.pm/finch/Finch.Telemetry.html>
- Req: <https://hexdocs.pm/req/Req.html>
