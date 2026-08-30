# ADR-0007 — Integration Packages fora de `apps/`

- Status: Accepted
- Estado de implementação: ESTRUTURA + BUILD CONTRACT RATIFICADOS; NÃO MATERIALIZADO

## Decisão

~~~text
packages/
├── build.exs
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib
    └── test
~~~

Cada Package será Mix project independente, não uma quinta platform application.

## Evolução

O ADR-0023 ratifica o mecanismo de 26C2:

- Manifest JSON v1 mínimo, identificado por SHA-256 dos bytes exatos;
- `PackageVersion.manifest_sha256` como vínculo persistido imutável;
- `packages/build.exs` como inventory literal e auditável;
- Mix path dependencies explícitas em `leafcutter_runtime`;
- refs locais ligadas a módulos Read/Write compilados;
- resolução em runtime por digest + projeção pública do Catalog.

Nenhuma dessas partes está materializada. A inventory pode permanecer vazia até a primeira
referência de produto em 26C3.

## Consequências

Build precisa ser explícito e auditável. Package não depende de internals de Core, Runtime ou
API. Diretório não listado no inventory não entra no build/release.
