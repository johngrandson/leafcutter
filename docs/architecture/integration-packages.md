# Integration Packages

> **Status: PARCIALMENTE MATERIALIZADO.** A authority relacional do Catalog e o contract de
> Manifest/binding em `leafcutter_connectors` existem. Build inventory, module resolution e
> package de produto permanecem pendentes.

## Estado materializado

O Catalog materializa:

~~~text
Package
└── immutable PackageVersion
    ├── exactly one source endpoint
    └── one or more ordered destination endpoints
~~~

Cada endpoint pinna uma Operation compatível com seu role e uma ContractVersion executável. A
publicação é atômica e o PostgreSQL impede topologia incompleta, append tardio, update e delete.

## Estrutura física ratificada

~~~text
packages/
├── build.exs
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib
    └── test
~~~

Cada Package é um Mix project independente fora de `apps/`. Ele é uma OTP application de
produto, não uma quinta platform application.

## Manifest v1 materializado na boundary

O Manifest v1 contém somente:

~~~text
manifest_version = 1
package.name + package.version
one source ref
one or more ordered destination refs
~~~

Os bytes exatos produzem um SHA-256 lowercase. O parser bounded e a binding compilada já
calculam e embutem esse digest. Os passos seguintes o persistirão em PackageVersion e repetirão
o valor em `packages/build.exs`.

O JSON não contém UUID, app atom, module name, config concreta, credential ou raw secret.
Operation e ContractVersion permanecem pinadas exclusivamente na projeção relacional.

## Binding compilada

Package code usa `LeafcutterConnectors.Package` para ligar refs locais a módulos literais:

~~~text
source ref      → Operation.Read module
destination ref → Operation.Write module
~~~

A macro valida cobertura, ordem, unicidade e behaviours em compile time e embute somente a
projeção validada, o digest e módulos literais. `leafcutter_runtime` ainda deverá resolver o
digest na inventory compilada e combinar os módulos com `operation_id` e
`contract_version_id` lidos pela API pública do Catalog. O resultado será in-memory e não
alterará RunSnapshot v1.

## Build e release

`packages/build.exs` lista explicitamente app, path, binding module e manifest digest. Não
existe glob ou auto-discovery. Cada entry vira Mix path dependency de `leafcutter_runtime`,
entrando na dependency closure da release.

Um diretório não listado não compila nem resolve. `mix quality` deverá validar inventory,
manifest/digest, Mix app, behaviours, testes do package e presença na release.

## Imutabilidade e legado

PackageVersion publicada continua imutável. A coluna `manifest_sha256` será nullable somente
para rows históricas; novas publicações exigirão digest. Versões legadas permanecerão legíveis,
mas não poderão originar novos deployments ou Runs.

## Dependências

Package pode depender de contracts públicos de `leafcutter_connectors` e dependencies Mix
próprias. Não depende de Core, Runtime ou API.

## Fora do primeiro caminho

- package de produto, autenticação e vendor semantics (26C3);
- SourceIdentity/Transformation/Enrichment/Interceptor no Manifest;
- remote registry/distribution;
- artifact signing/provenance;
- hot install/uninstall;
- package isolation;
- retention e rolling upgrade de package code;
- dependency solver de domínio.

## Referências

- `docs/decisions/ADR-0007-integration-packages.md`
- `docs/decisions/ADR-0023-package-manifest-build-binding-module-resolution.md`
- `docs/specifications/package-manifest-v1.md`
- `docs/architecture/connectors-operations-transports.md`
