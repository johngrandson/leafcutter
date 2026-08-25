# Error and Retry Model

- Status: Accepted baseline

```text
validation
authentication
rate_limited
timeout
temporary
permanent
```

## Retry

```text
validation      no automatic retry
authentication  blocked until configuration/secret changes
rate_limited    retry at Retry-After/backoff
timeout         retry
temporary       retry
permanent       no automatic retry
```

Delivery retryable volta a `pending` com `available_at`. Attempt registra cada try.

Write Operation com resposta parcial retorna resultados por item; erro da request inteira não confirma nenhum item.
