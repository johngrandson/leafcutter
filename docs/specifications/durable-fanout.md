# Durable Fan-out

- Status: Accepted baseline

Para cada persistence batch:

```text
insert Records
insert N Deliveries per Record
advance Checkpoint
COMMIT
```

Tudo na mesma transação.

Destination Producers claimam Deliveries `pending` e disponíveis. Locks são curtos e liberados antes de side effects externos.

Sem fila externa na primeira arquitetura. Se Postgres se tornar gargalo comprovado, Delivery permanece no domínio e o mecanismo de transporte do backlog pode evoluir.
