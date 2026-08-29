# Operation contract

- Estado: CONCEITO RATIFICADO — CONTRACT CONCRETO DO SLICE 26B AINDA ABERTO

Operation já existe como metadata imutável no Catalog, com `ref` e role source/destination. Esta specification trata exclusivamente do behaviour executável futuro.

O ADR-0019 separou a fronteira executável em três slices. ContractVersion + JSON Schema/JSV pertence ao Slice 26A e não materializa nenhum item desta specification. Signatures, structs, invocation inputs e results de Operation serão ratificados no Slice 26B. Transport HTTP pertence ao Slice 26C.

## Read Operation

Direção conceitual de paginação:

~~~text
fetch(config, cursor)
→ records
→ next_cursor
→ done?
→ metadata
~~~

## Write Operation

Direção conceitual para batch validado e resultado por item:

~~~text
success + optional destination identity
error + normalized operation error
~~~

## Regras já preservadas

- sem acesso a internals de Integration/Run;
- auth/config chegam resolvidos;
- partial success será explícito;
- Transport executa protocolo;
- error taxonomy seguirá `error-retry-model.md`.

## Ainda a ratificar no Slice 26B

- module/behaviour names;
- signatures e typespecs;
- invocation structs;
- read/write result structs;
- cursor e pagination semantics;
- partial batch ordering e completeness;
- pontos source/destination de `Contracts.validate/2`;
- relação com retry taxonomy.

Não escolher esses detalhes durante a materialização do Slice 26A.
