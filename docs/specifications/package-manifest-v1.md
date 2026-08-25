# Package Manifest v1 - Draft

- Status: Proposed

O schema definitivo ainda será desenhado. Esta lista registra responsabilidades, não campos congelados.

## Deve declarar

- package id/version;
- source Connector/Operation/Contract;
- identity config quando a Operation não souber;
- destinations;
- destination Connector/Operation/Contract;
- Transformation module;
- optional Enrichments;
- explicit Interceptors;
- dependencies e versões;
- configuration requirements;
- defaults/constraints permitidos.

## Não deve declarar

- secrets;
- credential values;
- Run state;
- environment ownership;
- arbitrary transformation expressions;
- runtime PIDs/queues;
- client-specific production data.

## Validation

- JSON Schema + JSV;
- referenced Contracts valid;
- modules known at build/startup;
- dependencies resolvable;
- no dynamic atom creation from untrusted input.
