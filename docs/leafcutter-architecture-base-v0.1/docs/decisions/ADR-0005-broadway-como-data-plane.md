# ADR-0005 - Broadway como data plane

- Status: Accepted

## Decisão

Broadway controla demand, concorrência, batching, backpressure e supervision das pipelines de Source, Enrichment e Destination.

RunCoordinator permanece no control plane e fora do fluxo por Record.

## Consequências

- menos processos e abstrações customizadas;
- uma pipeline independente por destination;
- retries continuam responsabilidade do durable producer/modelo de Delivery;
- configuração dinâmica precisa respeitar boas práticas do Broadway.
