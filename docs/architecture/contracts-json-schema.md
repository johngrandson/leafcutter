# Contracts e JSON Schema

> **Status: PARCIALMENTE MATERIALIZADO.** Contract e ContractVersion existem somente como identidades; conteúdo JSON Schema e validação JSV permanecem ratificados para um estágio posterior.

## Estado materializado

O Catalog já possui a autoridade de identidade necessária para resolução:

```text
Contract
└── immutable ContractVersion
    ├── version
    └── published_at
```

`Leafcutter.Catalog.Contracts` cria e lê identidades Contract e publica identidades ContractVersion. O conteúdo executável do contract não é aceito nem persistido neste slice.

## Decisão

Contracts externos usarão JSON Schema Draft 2020-12 e validação via JSV.

```text
external payload
→ source ContractVersion
→ trusted map
→ Transformation
→ destination ContractVersion
→ valid external payload
```

## Versionamento

```text
Contract
└── immutable ContractVersion
```

Nova versão não altera Runs históricos nem PackageVersions publicadas.

A identidade versionada já está materializada. O conteúdo JSON Schema associado a cada ContractVersion permanece futuro.

## Source e destination

Source validation protege o runtime contra dados externos inesperados. Destination validation protege o sistema externo contra erros do Package.

## Compilação futura

Validators serão compilados e reutilizados. Referências remotas precisarão ser resolvidas e congeladas antes da execução; uma Run não dependerá da internet para interpretar schema.

## Limites

JSON Schema valida estrutura e constraints declarativas. Não será transformado em framework de regras internas de domínio.

## Ainda aberto

- persistência e versionamento do conteúdo JSON Schema de ContractVersion;
- cache/compilation strategy;
- resolução de `$ref`;
- error representation pública;
- limites de schema e segurança;
- integração exata com RunSnapshot.
