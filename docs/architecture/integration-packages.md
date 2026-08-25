# Integration Packages

## Definição

Um Integration Package é a unidade versionada que descreve e implementa uma topologia de integração.

```text
Package Version
→ código + manifest + contracts + dependency versions
```

Package não é uma Integration de cliente. A relação é:

```text
Package Version
    ↓ configured as
Integration
    ↓ executed as
Run
```

## Estrutura alvo

```text
packages/
└── customer_distribution/
    ├── manifest.json
    ├── schemas/
    │   ├── source_customer.json
    │   ├── crm_customer.json
    │   └── billing_customer.json
    ├── lib/
    │   └── customer_distribution/
    │       ├── crm.ex
    │       ├── billing.ex
    │       ├── enrichments/
    │       └── interceptors/
    └── test/
        ├── fixtures/
        └── customer_distribution_test.exs
```

## `manifest.json`

O manifest é declarativo e validado por JSON Schema + JSV.

Ele descreve:

- identidade e versão do Package;
- Source Connector/Operation;
- Source Contract;
- destinations;
- Destination Contracts;
- Transformation modules;
- Enrichment definitions opcionais;
- Interceptors explícitos;
- dependency versions;
- defaults, constraints e configuration requirements.

Ele não contém:

- secrets;
- URLs reais de cliente quando environment-specific;
- credenciais;
- estado de Run;
- checkpoints;
- regras RBAC;
- lógica de transformação em strings/DSL.

## Código

Transformation, Enrichment preparation e Interceptor são módulos Elixir normais. Código in-package é compilado, testado, versionado e revisado em Git.

## Versionamento

Package Versions são imutáveis.

```text
customer_distribution@1.3.0
→ connector versions congeladas
→ contract versions congeladas
→ Git commit de origem registrado
```

Upgrade é explícito. Runs antigos continuam apontando para a versão original.

## Build inicial

A separação física `apps/` vs `packages/` é canônica:

```text
apps/
→ plataforma

packages/
→ integrações executadas pela plataforma
```

A primeira estratégia de build pode compilar os Packages com a mesma release, mas não deve misturar seu código nos contexts da plataforma.

## Tooling

A interface inicial de desenvolvimento será Mix:

```bash
mix platform.package.validate
mix platform.package.test
mix platform.package.build
mix platform.package.publish
```

Os nomes exatos das tasks serão definidos quando o package lifecycle for implementado. Não criar CLI própria cedo.
