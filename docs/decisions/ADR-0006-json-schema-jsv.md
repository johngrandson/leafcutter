# ADR-0006 — JSON Schema 2020-12 + JSV

- Status: Accepted
- Estado de implementação: NÃO MATERIALIZADO

## Decisão

Contracts externos usarão JSON Schema Draft 2020-12 e JSV.

## Futuro ratificado

Source e destination payloads serão validados. ContractVersions publicadas serão imutáveis. Validators serão compilados/reutilizados e referências remotas resolvidas antes da execução.

## Consequências

JSON Schema protege boundaries externas, mas não vira framework de regras internas do Leafcutter.
