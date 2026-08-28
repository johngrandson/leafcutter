# Package Manifest v1

- Estado: DRAFT / ABERTO

A projeção relacional interna de PackageVersion já está materializada no Catalog. Isso não torna canônicos o JSON Schema, os field names nem o formato físico deste manifest.

## Estrutura conceitual

```text
package identity/version
exactly one source
one or more destinations
ConnectorVersion + Operation refs
ContractVersion refs
SourceIdentity rule
config contract
transformations
enrichments
interceptors
```

## Regras já ratificadas

- PackageVersion publicada é imutável;
- Package não contém secrets;
- topology inicial é 1 Source → 1..N Destinations;
- PackageDependency não faz parte do V1;
- packages ficam fora de `apps/`.

## Ainda não canônico

- JSON Schema completo;
- field names;
- semantic version constraints;
- artifact hashes/signatures;
- build metadata;
- config schema embedding/reference;
- validation CLI.

Exemplos atuais não devem ser tratados como contract estável.
