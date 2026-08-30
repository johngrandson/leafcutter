# Integration Packages

> **Status: PARCIALMENTE MATERIALIZADO.** O Manifest v1 e a binding compilada existem em
> `leafcutter_connectors`; build inventory e packages de produto permanecem pendentes.

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

Quando o passo 37 for materializado, somente entries literais de `build.exs` entrarão no
dependency graph do Mix e na release; descoberta por varredura de diretórios é proibida.
`packages/build.exs` e os packages executáveis ainda não existem. A inventory de produção
permanecerá vazia até o Slice 26C3 selecionar o primeiro sistema externo e a primeira
Operation reais.

Código-fonte, metadata do Mix, documentação in-code e testes dos packages devem ser escritos
em inglês. Um package poderá depender dos contracts públicos de `leafcutter_connectors`,
nunca de internals de Core, Runtime ou API.

Consulte:

- `docs/decisions/ADR-0023-package-manifest-build-binding-module-resolution.md`
- `docs/specifications/package-manifest-v1.md`
