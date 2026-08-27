# Durable fan-out

- Status: Accepted baseline
- Estado de implementação: NÃO MATERIALIZADO

## Contract ratificado

Para cada Record source e N destinations:

```text
1 Record
+ N Delivery intents
+ Checkpoint advancement
= one PostgreSQL transaction
```

Checkpoint só avança após commit.

## Recovery

Crash antes do commit repete a página. Crash depois do commit deixa trabalho durável para DestinationBroadways.

## Fencing

A escrita deverá incluir ownership token da Run na mesma transação.

## Ainda aberto

- schema e indexes;
- batch size;
- conflict/idempotency keys;
- payload storage;
- Delivery initial status;
- error mapping.
