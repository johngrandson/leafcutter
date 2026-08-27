# Error and retry model

- Estado: RATIFICADO — NÃO MATERIALIZADO

Taxonomia inicial:

```text
validation
authentication
rate_limited
timeout
temporary
permanent
```

Política:

```text
validation      no automatic retry
authentication  wait for config/secret change
rate_limited    retry later
timeout         retry
temporary       retry
permanent       no automatic retry
```

Delivery retryable usará `available_at` futuro e incrementará attempt count. Broadway não será o scheduler.

Ainda precisam ser fechados tipos Elixir, serialized shape, backoff, max attempts e relação com HTTP status/vendor errors.
