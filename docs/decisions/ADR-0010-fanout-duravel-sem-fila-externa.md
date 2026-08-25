# ADR-0010 - Fan-out durável sem fila externa inicial

- Status: Accepted

## Decisão

Persistir em batch:

```text
Records
N Deliveries por Record
Checkpoint
```

na mesma transação. Destination Broadways consomem Deliveries persistidas de forma independente.

Não usar Kafka/RabbitMQ/PGMQ inicialmente. Postgres funciona como backlog durável, não como conceito de domínio chamado spool.

## Consequências

- recovery e auditoria simples;
- mais write load no Postgres;
- insert/update em batch e poucos estados duráveis;
- fila externa só entra por evidência de gargalo.
