# ADR-0005 — Broadway como data plane

- Status: Accepted
- Estado de implementação: NÃO MATERIALIZADO

## Decisão

Broadway será usado para demand, bounded concurrency, batching, backpressure e failure isolation no processamento de Records/Deliveries.

## Estado atual

Somente o control plane OTP existe. Não há SourceBroadway, EnrichmentBroadway ou DestinationBroadway.

## Consequências

- não implementar worker pools manuais equivalentes;
- RunCoordinator permanece fora do data path;
- cada destination pode ter pipeline e backlog independentes;
- retry scheduling continua durável no modelo de Delivery, não no Broadway.
