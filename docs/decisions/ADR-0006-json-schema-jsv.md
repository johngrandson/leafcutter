# ADR-0006 — JSON Schema 2020-12 + JSV

- Status: Accepted
- Estado de implementação: PARCIAL — EXECUÇÃO MATERIALIZADA ATÉ PACKAGEVERSION; PROPAGAÇÃO PENDENTE

## Decisão

Contracts externos usarão JSON Schema Draft 2020-12 e JSV.

## Estado materializado

Novas ContractVersions persistem schema Draft 2020-12 imutável, são validadas e construídas com JSV na publicação e expõem compilação e validação reutilizáveis. Novas PackageVersions rejeitam ContractVersions identity-only legadas.

## Futuro ratificado

Source e destination payloads serão validados. A executabilidade ainda será propagada por EnvironmentDeployment e pela resolução de Run. Uma futura adoção de referências externas exigirá resolução e empacotamento antes da publicação.

## Consequências

JSON Schema protege boundaries externas, mas não vira framework de regras internas do Leafcutter.

## Evolução

O ADR-0018 materializou `ContractVersion` inicialmente como identity-only. O ADR-0019 ratificou o primeiro slice executável: schema JSONB object/boolean imutável, legado nullable não executável, publicação com build completo, refs somente locais, APIs `Contracts.compile/1` e `validate/2`, e propagação da executabilidade até a resolução de Run. A implementação alcança hoje a boundary de PackageVersion; Deployment e Run permanecem pendentes.

O ADR-0019 não materializa behaviours de Operation, Transport HTTP ou data plane.
