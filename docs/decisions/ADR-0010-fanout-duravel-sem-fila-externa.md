# ADR-0010 — Fan-out durável sem fila externa inicial

- Status: Accepted
- Estado de implementação: NÃO MATERIALIZADO

## Decisão

Records, Deliveries e Checkpoint serão persistidos no PostgreSQL antes do processamento de destinos. Delivery será o backlog durável inicial.

## Consequências

- sem Kafka/RabbitMQ/Redis por antecipação;
- checkpoint não avança sem fan-out committed;
- external queue só entra após gargalo comprovado;
- mesmo com fila futura, Delivery continua entidade de domínio.
