# Source identity

- Estado: RATIFICADO — NÃO MATERIALIZADO

## Conceitos

```text
Record.id
→ occurrence inside a Run

SourceIdentity
→ stable source entity identity

PayloadHash
→ content fingerprint
```

SourceIdentity pode ser field simples ou composição determinística conforme PackageVersion/Operation.

```text
same SourceIdentity + different PayloadHash
→ same entity, changed content
```

Ainda precisam ser fechados canonical encoding, composite keys, null handling, hashing algorithm e uniqueness constraints.
