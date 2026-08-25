# Transformations, Enrichments e Interceptors

## Transformation

Responsabilidade: converter um payload válido de origem em payload(s) de negócio para um destino.

É Elixir puro e não executa side effects.

Retornos oficiais:

```elixir
{:ok, payload}        # 1 -> 1
{:ok, [payloads]}     # 1 -> N
:skip                 # 1 -> 0
{:error, reason}      # falha controlada
```

Cada payload de `1 -> N` é validado individualmente pelo Destination Contract.

Transformation pode usar:

- `if`, `case`, `cond`;
- pattern matching;
- `Enum`, `Map`, `String`, datas;
- regras condicionais;
- cálculos;
- normalização;
- config imutável do Run Snapshot.

Não pode chamar HTTP, Repo, Oban, PubSub, filesystem ou secrets.

## Enrichment

Responsabilidade: executar uma consulta externa opcional no meio do fluxo para obter dados adicionais.

```text
validated source
    ↓
optional Enrichment
    ↓
source + enrichment result
    ↓
Transformation
```

O Package prepara o input de forma pura; Connector/Operation executa o side effect; o resultado é persistido. Enrichment é uma unidade durável e retryable.

No OTP, Enrichment é uma Broadway pipeline opcional dentro da árvore do Run. Não criar uma hierarquia manual de workers quando Broadway já resolve lifecycle e backpressure.

Primeiro suportar Enrichment compartilhado antes do fan-out. Enrichment específico por destination pode reutilizar a mesma primitive posteriormente.

## Interceptor

Responsabilidade: adaptar ou observar a comunicação, não o dado de negócio.

Pode modificar:

- headers;
- query params;
- URL;
- assinatura;
- correlation/tracing metadata.

Inicialmente não modifica o body depois da validação do Destination Contract.

Interceptors são explícitos no Package. Não criar cadeias globais invisíveis.

## Funções auxiliares

Lógica reutilizável continua como módulos/funções Elixir normais dentro do Package. Não existe uma entidade de plataforma chamada Function.
