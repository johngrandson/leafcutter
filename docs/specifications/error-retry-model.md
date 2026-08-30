# Error and retry model

- Estado: RATIFICADO — NÃO MATERIALIZADO

## Operation error in-memory

O ADR-0021 controla o `LeafcutterConnectors.Operation.Error` materializado para callbacks executáveis:

~~~elixir
%Operation.Error{
  category: :validation
            | :authentication
            | :rate_limited
            | :timeout
            | :temporary
            | :permanent,
  code: "stable_code",
  message: nil,
  retry_after_ms: nil,
  metadata: %{}
}
~~~

O struct e sua validação pura estão materializados in-memory. Eles não definem a representação serializada futura de Attempt/Delivery; por isso o estado geral desta specification permanece não materializado.

Não existe campo `retryable`; o caller deriva a policy da category:

| Categoria | Retry automático | Estado esperado |
|---|---|---|
| `validation` | não | terminal para a invocation/item atual |
| `authentication` | não temporizado | bloqueado até recuperação explícita |
| `rate_limited` | sim | disponível novamente no futuro |
| `timeout` | sim | disponível novamente; efeito externo pode ser desconhecido |
| `temporary` | sim | disponível novamente no futuro |
| `permanent` | não | terminal sem mudança da definição |

`retry_after_ms` é somente um hint não negativo para `:rate_limited` ou `:temporary`.
Backoff e limites futuros continuam sendo responsabilidade da policy do runtime.

Code, message e metadata são sanitizados. Nenhum deles recebe credential, config, payload,
request/response body, headers, stacktrace ou raw vendor message.

## Write partial success

Um `{:ok, Write.Result.t()}` possui exatamente um outcome por item. Cada item error pode ter
category distinta.

Um `{:error, Operation.Error.t()}` no callback inteiro significa ausência de classificação
completa e confiável. Quando essa falha é retryable, o runtime assume que efeitos externos
podem ter ocorrido e preserva at-least-once.

## HTTP boundary

O ADR-0022 materializa `HTTP.Error` como erro de protocolo/conexão separado de
`Operation.Error`. Todo status HTTP bem-formado continua sendo Response. A Operation futura
decide status, `Retry-After` e vendor body, produzindo somente code/metadata allowlisted.

Timeout de Transport normalmente vira `Operation.Error{category: :timeout}`; pool/connection
unavailable normalmente vira `:temporary`. A matriz concreta permanece em 26C3 porque depende
dos sistemas e endpoints escolhidos para o fluxo completo.

## Delivery futura

Delivery retryable usará `available_at` futuro e incrementará attempt count. Broadway não
será o scheduler.

Ainda precisam ser ratificados:

- serialized error shape de Attempt/Delivery;
- Delivery statuses para authentication e terminal errors;
- backoff, jitter e max attempts;
- reset/recovery explícito após mudança de configuração;
- matriz concreta de HTTP status, headers e vendor errors para cada Operation do fluxo 26C3.
