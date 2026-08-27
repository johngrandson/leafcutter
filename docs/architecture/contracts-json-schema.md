# Contracts e JSON Schema

> **Status: RATIFICADO — NÃO MATERIALIZADO.**

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

## Source e destination

Source validation protege o runtime contra dados externos inesperados. Destination validation protege o sistema externo contra erros do Package.

## Compilação futura

Validators serão compilados e reutilizados. Referências remotas precisarão ser resolvidas e congeladas antes da execução; uma Run não dependerá da internet para interpretar schema.

## Limites

JSON Schema valida estrutura e constraints declarativas. Não será transformado em framework de regras internas de domínio.

## Ainda aberto

- schema físico de Contract/ContractVersion;
- cache/compilation strategy;
- resolução de `$ref`;
- error representation pública;
- limites de schema e segurança;
- integração exata com RunSnapshot.
