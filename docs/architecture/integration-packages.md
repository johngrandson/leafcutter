# Integration Packages

> **Status: ESTRUTURA RATIFICADA — NÃO MATERIALIZADA.**

## Papel

Package é código e metadata reutilizáveis. Não contém credenciais nem configuração concreta de cliente.

```text
Package
└── immutable PackageVersion
    ├── exactly one Source
    ├── one or more Destinations
    ├── ConnectorVersion + Operation refs
    ├── ContractVersion refs
    ├── SourceIdentity rule
    ├── Transformations
    ├── optional Enrichments
    └── explicit Interceptors
```

## Estrutura física ratificada

```text
packages/<package>/
├── mix.exs
├── manifest.json
├── lib
└── test
```

Cada Package é um Mix project independente fora de `apps/`.

## Imutabilidade

PackageVersion publicada é imutável. Evolução cria nova versão. `PackageDependency` não faz parte do V1.

## Dependências

Package pode depender de contracts públicos de `leafcutter_connectors`. Não depende de internals de runtime ou API.

## Build futuro

Packages instalados serão compilados na mesma release inicial. O mecanismo físico para incluí-los no dependency graph continua aberto e deverá ser explícito e auditável.

## Manifest

O JSON Schema definitivo do `manifest.json` ainda não está fechado. Não tratar exemplos atuais como contract final.

## Não antecipar

- registry remoto;
- package isolation;
- dependency solver complexo;
- filesystem auto-discovery implícito;
- standalone CLI antes de Mix tooling se mostrar insuficiente.
