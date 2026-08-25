# Source Identity

- Status: Accepted baseline

## Conhecida

Connector/Operation conhecida define internamente como extrair a Source Identity.

## Generic/custom

Manifest declara forma simples:

```json
"identity": "id"
```

ou:

```json
"identity": ["company_id", "customer_id"]
```

Sem função Elixir customizada inicialmente.

## Conceitos distintos

```text
Record ID       internal occurrence
Source Identity stable external entity
Payload Hash    content fingerprint
```
