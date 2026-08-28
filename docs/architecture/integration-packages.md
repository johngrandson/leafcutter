# Integration Packages

> **Status: PARCIALMENTE MATERIALIZADO.** A authority e a projeção relacional do Catalog existem; manifest, código executável e build permanecem futuros.

## Estado materializado

O Catalog materializa a authority necessária para resolução:

```text
Package
└── immutable PackageVersion
    ├── exactly one source endpoint
    └── one or more ordered destination endpoints
```

Cada endpoint pinna uma Operation compatível com seu role e uma ContractVersion. A publicação é atômica e o PostgreSQL impede topologia incompleta, append tardio, update e delete. Essa projeção interna não ratifica field names do manifest.

## Papel

O Integration Package futuro combina código e metadata reutilizáveis. Não contém credenciais nem configuração concreta de cliente.

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

PackageVersion publicada já é imutável no Catalog. Evolução cria nova versão. `PackageDependency` não faz parte do V1.

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
