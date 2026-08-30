# Package Manifest v1

- Estado: PARCIALMENTE MATERIALIZADO — PASSO 35 CONCLUÍDO
- Decisão: `docs/decisions/ADR-0023-package-manifest-build-binding-module-resolution.md`

## Objetivo

Definir o primeiro contract físico que liga uma PackageVersion imutável a módulos Read/Write
já compilados, sem persistir nomes de módulos, converter strings em atoms ou descobrir packages
pelo filesystem.

O V1 cobre somente identidade do manifest, topologia de refs, inclusão explícita no build e
resolução compilada. Não publica uma Operation real e não altera RunSnapshot v1.

## Ownership

~~~text
leafcutter_core
└── PackageVersion.manifest_sha256 + relational endpoint authority

leafcutter_connectors
└── LeafcutterConnectors.Package
    └── Manifest + compiled endpoint binding contract

leafcutter_runtime
└── LeafcutterRuntime.ExecutablePackages
    └── Catalog projection + compiled inventory composition

repository build boundary
└── packages/build.exs
~~~

Packages dependem de APIs públicas de `leafcutter_connectors`. Não dependem de Core, Runtime
ou API.

## Layout físico

~~~text
packages/
├── build.exs
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib/
    └── test/
~~~

Cada diretório é um Mix project independente e uma OTP application sem supervisor próprio por
default. Estar fisicamente sob `packages/` não inclui o project no build; somente uma entry
explícita em `packages/build.exs` faz isso.

## Documento JSON

Exemplo completo de Manifest v1:

~~~json
{
  "manifest_version": 1,
  "package": {
    "name": "Example synchronization",
    "version": "2026.08"
  },
  "source": {
    "ref": "source"
  },
  "destinations": [
    {
      "ref": "destination"
    }
  ]
}
~~~

### JSON Schema Draft 2020-12

~~~json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "urn:leafcutter:package-manifest:v1",
  "type": "object",
  "required": [
    "manifest_version",
    "package",
    "source",
    "destinations"
  ],
  "additionalProperties": false,
  "properties": {
    "manifest_version": {
      "const": 1
    },
    "package": {
      "type": "object",
      "required": [
        "name",
        "version"
      ],
      "additionalProperties": false,
      "properties": {
        "name": {
          "type": "string",
          "minLength": 1,
          "maxLength": 255
        },
        "version": {
          "type": "string",
          "minLength": 1,
          "maxLength": 255
        }
      }
    },
    "source": {
      "$ref": "#/$defs/endpoint"
    },
    "destinations": {
      "type": "array",
      "minItems": 1,
      "maxItems": 1000,
      "uniqueItems": true,
      "items": {
        "$ref": "#/$defs/endpoint"
      }
    }
  },
  "$defs": {
    "endpoint": {
      "type": "object",
      "required": [
        "ref"
      ],
      "additionalProperties": false,
      "properties": {
        "ref": {
          "type": "string",
          "minLength": 1,
          "maxLength": 255
        }
      }
    }
  }
}
~~~

O decoder rejeita UTF-8 inválido e chaves duplicadas em qualquer objeto JSON. O schema é construído
com JSV sob Draft 2020-12. Uma validação pura complementar rejeita:

- name, version ou ref contendo somente whitespace;
- source ref repetido em destinations;
- qualquer ref duplicado no conjunto;
- improper lists ou termos que não vieram de JSON.

A comparação de destinations com a ordem da projeção do Catalog pertence à resolução do
runtime, não à validação isolada do documento.

## Limites

O limite raw é aplicado antes do decode. Profundidade e contagem de nós são verificadas
imediatamente após o decode e antes do build JSV:

| Limite | Valor |
|---|---:|
| raw `manifest.json` | 1 MiB |
| profundidade estrutural | 64 |
| nós JSON | 10.000 |
| destinations | 1.000 |

Não existe `:infinity`. Overflow falha o build sem incluir conteúdo raw no erro.

## Campos e semântica

| Campo | Tipo | Regra |
|---|---|---|
| `manifest_version` | integer | exatamente `1` |
| `package.name` | string | igual a `Package.name` |
| `package.version` | string | igual a `PackageVersion.version` |
| `source.ref` | string | exatamente uma source |
| `destinations` | non-empty array | ordem preservada |
| `destinations[].ref` | string | único no manifest inteiro |

Os refs são locais à PackageVersion. Eles conectam manifest, projection e binding compilada.
Não são module names. Name, version e refs são comparados por igualdade binária após o decode,
sem trim, case folding ou normalização Unicode.

## Dados deliberadamente ausentes

Manifest v1 não contém:

- `package_id`, `package_version_id`, `operation_id` ou `contract_version_id`;
- ConnectorVersion/Operation/ContractVersion duplicados;
- app atom ou module name;
- config concreta, Connection, SecretVersion ou credential;
- SourceIdentity;
- Transformation, Enrichment ou Interceptor;
- dependency solver metadata;
- URL de distribuição, assinatura ou artifact digest.

A projeção relacional continua sendo a única authority para Operation e ContractVersion. O
manifest permanece portável entre bancos.

## Digest

O digest é calculado sobre os bytes exatos do arquivo:

~~~elixir
@spec manifest_sha256(binary()) :: String.t()
def manifest_sha256(manifest_bytes) do
  manifest_bytes
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16(case: :lower)
end
~~~

Regras:

- algoritmo fixo SHA-256;
- representação lowercase hex com 64 caracteres ASCII;
- nenhuma canonicalização JSON;
- nenhuma normalização de newline, BOM ou whitespace;
- qualquer mudança de byte exige atualizar o inventory e publicar outra PackageVersion;
- duplicate digest no inventory ou Catalog é inválido.

`manifest_sha256` não é assinatura nem hash do código compilado. A release/commit pinna o
código no primeiro caminho.

## Persistência em PackageVersion

Campo novo:

~~~text
PackageVersion.manifest_sha256
→ lowercase hex SHA-256
→ immutable
→ globally unique
→ nullable only for historical rows
~~~

Toda publicação nova exige o campo. Rows históricas `nil` permanecem legíveis, mas não podem
ser usadas por novo deployment/replacement ou nova Run resolvida. Não existe backfill por name,
version, ref ou filesystem.

RunSnapshot v1 não recebe campo novo. O runtime lê o digest da PackageVersion imutável
referenciada por `definition.package_version_id`.

## Contract compilado do package

Módulos ratificados:

~~~text
LeafcutterConnectors.Package
LeafcutterConnectors.Package.Manifest
~~~

Uso esperado:

~~~elixir
defmodule ExampleSync.Package do
  use LeafcutterConnectors.Package,
    manifest: Path.expand("../../manifest.json", __DIR__),
    source: {"source", ExampleSync.Read},
    destinations: [{"destination", ExampleSync.Write}]
end
~~~

A macro lê e valida `manifest.json` durante a compilação, registra o arquivo como
`@external_resource` e embute o manifest validado e o digest no BEAM. Nenhum callback acessa o
filesystem em runtime.

O contract materializado expõe funções puras equivalentes a:

~~~elixir
@callback manifest() :: LeafcutterConnectors.Package.Manifest.t()
@callback manifest_sha256() :: String.t()
@callback source() :: {String.t(), module()}
@callback destinations() :: [{String.t(), module()}]
@callback resolve(String.t(), :source | :destination) ::
            {:ok, module()} | {:error, :not_found}
~~~

Invariantes:

- exatamente um source tuple;
- destination tuples não vazias e ordenadas;
- cobertura exata dos refs do manifest;
- nenhuma binding duplicada ou extra;
- source module implementa `Operation.Read`;
- destination modules implementam `Operation.Write`;
- callbacks não recebem UUID, config ou credentials;
- `@external_resource` aponta para o `manifest.json` raiz do próprio package;
- nenhum processo OTP é criado.

O manifest raw não é retornado, inspecionado ou logado.

### Estado materializado no passo 35

`LeafcutterConnectors.Package.Manifest` materializa parsing bounded, duplicate-key detection,
JSON Schema Draft 2020-12 com JSV, validação semântica complementar e SHA-256 dos bytes exatos.
`LeafcutterConnectors.Package` materializa bindings literais Read/Write, cobertura e ordem
exatas, module uniqueness, behaviour conformance, resolução pura e callbacks sem acesso ao
filesystem. Os testes de conformance usam somente fixture test-only.

A macro exige path absoluto e registra exatamente esse arquivo em `@external_resource`. A
prova de que ele é o `manifest.json` raiz do Mix project listado permanece responsabilidade da
inventory do passo 37. Persistência no Catalog, inventory/release e resolução por projeção
continuam nos passos 36–38.

## Build inventory

Arquivo:

~~~text
packages/build.exs
~~~

Shape canônico:

~~~elixir
[
  %{
    app: :leafcutter_package_example_sync,
    path: "packages/example_sync",
    binding: ExampleSync.Package,
    manifest_sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
]
~~~

A lista contém trusted Elixir literals revisados em source control. Não aceita callbacks,
environment branching ou valores vindos de runtime config.

### Validação de entry

| Campo | Regra |
|---|---|
| `app` | atom literal, único, igual ao `:app` do Mix project |
| `path` | path UTF-8 relativo e único, sem traversal, com realpath contido em `packages/` |
| `binding` | module atom literal, único e pertencente ao app |
| `manifest_sha256` | lowercase hex SHA-256 único |

Keys desconhecidas e entries incompletas falham. Entries são processadas em ordem determinística
por `app`; a ordem não tem semântica de execução.

A inventory vazia é válida antes de 26C3.

## Mix dependency graph

`leafcutter_runtime` transforma cada entry validada em dependency `:path`. Não existe glob:

~~~elixir
{:leafcutter_package_example_sync,
 path: "../../packages/example_sync"}
~~~

O package declara `leafcutter_connectors` como path dependency compartilhada e pode declarar
dependencies externas próprias. Conflitos de dependency são erros normais do Mix e não recebem
um solver Leafcutter próprio.

Dependency direction:

~~~text
leafcutter_api
└── leafcutter_runtime
    ├── leafcutter_core
    ├── leafcutter_connectors
    └── installed packages
        └── leafcutter_connectors
~~~

Todos os package apps listados precisam aparecer na dependency/application closure da release.

## Resolução pública do runtime

Módulo:

~~~text
LeafcutterRuntime.ExecutablePackages
~~~

API:

~~~elixir
@spec resolve(Leafcutter.Catalog.PackageVersion.id()) ::
        {:ok, LeafcutterRuntime.ExecutablePackages.Binding.t()}
        | {:error, resolve_error()}
~~~

Algoritmo:

1. chamar `Leafcutter.Catalog.Packages.get_version/1`;
2. validar `manifest_sha256`;
3. encontrar a binding literal pelo digest;
4. comparar `Package.name` e `PackageVersion.version`;
5. comparar source ref/role;
6. comparar destination refs/roles/order;
7. validar modules/behaviours;
8. compor os módulos com IDs autoritativos dos endpoints.

A Binding resultante preserva:

~~~text
package_version_id
manifest_sha256
source ref + operation_id + contract_version_id + module
ordered destinations with the same fields
~~~

Ela é in-memory, não JSON, não persistida e não faz parte de RunSnapshot v1.

### Errors

~~~elixir
@type resolve_error ::
        :package_version_not_found
        | :package_not_bound
        | :package_not_installed
        | :manifest_mismatch
        | :invalid_binding
~~~

Semântica:

| Reason | Condição |
|---|---|
| `:package_version_not_found` | o ID não existe |
| `:package_not_bound` | a row não possui digest válido |
| `:package_not_installed` | o digest válido não existe na inventory da release |
| `:manifest_mismatch` | name, version, refs, roles ou ordem divergem |
| `:invalid_binding` | o módulo literal viola o contract compilado |

Reasons são allowlisted. Errors não carregam raw manifest, path, module string, Catalog struct,
stacktrace ou exception. Defects inesperados continuam visíveis.

## Deployment e Run

A materialização repete a proteção em duas bordas:

- novo EnvironmentDeployment create/replace rejeita PackageVersion histórica sem digest;
- `Runs.create_from_deployment/1` repete essa validação sob os locks já ratificados;
- o runtime também exige que o digest exista na release e que manifest/projection coincidam;
- qualquer falha ocorre antes de criar Run ou RunSnapshot;
- estado histórico não é reescrito.

Uma PackageVersion válida pode ser publicada antes do rollout da release. A ausência no build
é erro de disponibilidade de código no momento da resolução, não corrupção do Catalog.

## Quality e release gates

A materialização precisa provar:

### Manifest

- schema JSON válido e inválido;
- unknown fields;
- UTF-8 e whitespace;
- source/destination cardinalidade;
- duplicate refs;
- limits;
- digest byte-exact, inclusive diferenças de newline/whitespace.

### Binding

- exact coverage;
- role e order;
- missing/extra/duplicate module binding;
- Read/Write behaviour conformance;
- safe errors e ausência de raw manifest em Inspect/log.

### Inventory

- empty inventory;
- exact keys;
- duplicate app/path/module/digest;
- path traversal/absolute path;
- missing project/manifest;
- binding compilada a partir de outro arquivo que não o manifest raiz do package;
- Mix app mismatch;
- digest mismatch;
- unlisted directory não incluído.

### Runtime

- successful resolution preserving Catalog IDs/order;
- legacy PackageVersion;
- absent digest in release;
- name/version/topology mismatch;
- no `String.to_atom`, `Module.concat`, persisted module name ou filesystem scan;
- resolution failure creates no Run/RunSnapshot.

### Build e release

- every inventory path dependency compiles;
- package tests execute explicitly;
- umbrella quality includes package format/tests/Dialyzer;
- every inventory app exists in the release application closure;
- fixture packages remain test-only and do not count as 26C3.

## Semânticas proibidas

- module name no JSON, Catalog ou RunSnapshot;
- UUID-to-module application config;
- `String.to_atom/1`, `String.to_existing_atom/1` ou `Module.concat/1` sobre dados;
- filesystem glob/discovery para incluir packages;
- scan de modules/behaviours carregados;
- runtime `Code.eval_*`, `Code.require_file` ou dynamic code loading;
- hot install/uninstall;
- fallback para outro digest/version;
- auto-publication de Catalog rows no application start.

## Fora de escopo

- primeira Operation/Connector real;
- vendor auth, pagination, codec, status e error mapping;
- SourceIdentity, Transformations, Enrichments e Interceptors no manifest;
- package dependency domain model;
- remote registry/distribution;
- artifact hash/signature/provenance;
- package sandbox/isolation;
- package retention e rolling upgrade;
- persisted Attempt/Delivery errors;
- RunCoordinator execution, Broadway e durable fan-out.
