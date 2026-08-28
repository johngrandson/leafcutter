# Operation contract

- Estado: RATIFICADO — CONTRACT EXECUTÁVEL NÃO MATERIALIZADO

Operation já existe como metadata imutável no Catalog, com `ref` e role source/destination. Esta specification trata exclusivamente do behaviour executável ainda futuro.

## Read Operation

Normaliza paginação:

```text
fetch(config, cursor)
→ records
→ next_cursor
→ done?
→ metadata
```

## Write Operation

Recebe batch validado e preserva resultado por item:

```text
success + optional destination identity
error + normalized operation error
```

## Regras

- sem acesso a internals de Integration/Run;
- auth/config chegam resolvidos;
- partial success é explícito;
- Transport executa protocolo;
- error taxonomy segue `error-retry-model.md`.

Signatures, structs e behaviours finais serão ratificados com a primeira implementação HTTP.
