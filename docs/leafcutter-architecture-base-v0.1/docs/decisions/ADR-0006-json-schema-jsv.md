# ADR-0006 - JSON Schema Draft 2020-12 e JSV

- Status: Accepted

## Decisão

JSON Schema Draft 2020-12 é o contrato canônico dos payloads. JSV é o validator inicial. Runtime usa maps/lists/scalars compatíveis com JSON.

Schemas e referências são versionados, congelados e compilados fora do hot path.

## Consequências

- contratos portáveis;
- validação nas duas bordas;
- OpenAPI import futuro;
- nenhuma geração obrigatória de structs por schema;
- JSV não deve vazar pelo domínio inteiro.
