# Integration Packages

> **Status: PARCIALMENTE MATERIALIZADO.** Manifest, binding e build inventory existem;
> packages de produto e resolução pela projeção do Catalog permanecem pendentes.

Este diretório é a fronteira física reservada para o código executável de Integration
Packages. O layout ratificado é:

~~~text
packages/
├── build.exs
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib
    └── test
~~~

Somente entries literais de `build.exs` entram no dependency graph do Mix e na release;
descoberta por varredura de diretórios é proibida. A inventory de produção está vazia e
permanecerá assim até o Slice 26C3 selecionar o primeiro sistema externo e a primeira
Operation reais. A fixture usada para validar o contract fica sob testes do runtime, é
`only: :test` e não representa um package de produto.

Cada entry precisa declarar exatamente `app`, `path`, `binding` e `manifest_sha256`. O build
valida path/realpath, Mix project, dependency direction, manifest raiz, digest, ownership do
módulo, topology e behaviours antes de embutir a inventory. `mix quality` também prova a
closure da release e executa os gates próprios de cada package listado.

Como cada package é um Mix project independente, ele mantém seu próprio `.formatter.exs` e
declara Dialyxir como dependency somente de desenvolvimento/teste e `runtime: false`. As
ferramentas configuradas na umbrella não ficam disponíveis automaticamente dentro do project
do package.

Código-fonte, metadata do Mix, documentação in-code e testes dos packages devem ser escritos
em inglês. Um package poderá depender dos contracts públicos de `leafcutter_connectors`,
nunca de internals de Core, Runtime ou API.

Consulte:

- `docs/decisions/ADR-0023-package-manifest-build-binding-module-resolution.md`
- `docs/specifications/package-manifest-v1.md`
