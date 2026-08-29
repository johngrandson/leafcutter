# ADR-0006 — JSON Schema 2020-12 + JSV

- Status: Accepted
- Estado de implementação: PARCIAL — IDENTIDADE MATERIALIZADA; EXECUÇÃO RATIFICADA NO ADR-0019

## Decisão

Contracts externos usarão JSON Schema Draft 2020-12 e JSV.

## Futuro ratificado

Source e destination payloads serão validados. ContractVersions publicadas serão imutáveis. Validators serão compilados/reutilizados e referências remotas resolvidas antes da execução.

## Consequências

JSON Schema protege boundaries externas, mas não vira framework de regras internas do Leafcutter.

## Evolução

O ADR-0018 materializou `ContractVersion` inicialmente como identity-only. O ADR-0019 ratifica o primeiro slice executável: schema JSONB object/boolean imutável, legado nullable não executável, publicação com build completo, refs somente locais, APIs `Contracts.compile/1` e `validate/2`, e propagação da executabilidade até a resolução de Run.

O ADR-0019 não materializa behaviours de Operation, Transport HTTP ou data plane.
