# ADR-0023 — Package Manifest v1, build inventory e resolução compilada

- Status: Accepted
- Estado de implementação: MATERIALIZADO — PASSOS 35–38
- Data: 2026-08-30

## Contexto

O Slice 26C1 materializou uma boundary HTTP executável, mas o runtime ainda não possui uma
forma segura de selecionar módulos de Operation. A authority persistida é
`PackageVersion`: seus endpoints imutáveis pinam `Operation` e `ContractVersion`, enquanto
`RunSnapshot v1` congela somente o `package_version_id`, refs, contratos e Connections
resolvidas.

Um módulo Elixir não é uma identidade de domínio. Persistir nomes de módulos, derivá-los de
strings ou manter um map manual de UUID para módulo criaria uma segunda authority frágil,
acoplada a uma release específica. Também não é aceitável descobrir código varrendo
`packages/*` em runtime.

O mecanismo precisa simultaneamente:

- preservar `PackageVersion` como authority da topologia;
- manter módulos somente em código confiável já compilado;
- incluir packages locais no dependency graph e na release de forma explícita;
- detectar divergência entre manifest, projeção do Catalog e bindings compiladas;
- permitir que o mesmo manifest seja publicado em bancos diferentes sem carregar UUIDs;
- manter `RunSnapshot v1` inalterado;
- não antecipar uma Operation real, vendor mapping ou data plane.

## Decisão

### Escopo do Slice 26C2

O incremento 26C2 é dividido em quatro partes inseparáveis:

~~~text
Package Manifest JSON Schema v1
→ manifest digest persistido em PackageVersion
→ checked-in build inventory + explicit Mix path dependencies
→ compiled endpoint bindings + runtime resolution
~~~

O slice não cria um package de produto. Fixtures de conformance não contam como a referência
de 26C3.

### Separação de authorities

A responsabilidade fica dividida assim:

| Owner | Responsabilidade |
|---|---|
| `leafcutter_core` | PackageVersion, endpoints, `manifest_sha256` e leitura da projeção |
| `leafcutter_connectors` | Manifest/binding contract consumido por package code |
| `leafcutter_runtime` | inventory compilada e composição com APIs públicas do Catalog |
| `packages/build.exs` | lista confiável, explícita e revisável de packages da release |
| `packages/<package>` | manifest, módulos Read/Write e testes do package |

`leafcutter_connectors` não consulta Repo. `leafcutter_core` não depende de package code.
O runtime é o único composition root capaz de depender simultaneamente de Core, Connectors e
packages compilados.

### Package Manifest v1

O arquivo canônico é `packages/<package>/manifest.json`. O V1 possui somente a identidade
auditável do manifest e a topologia de refs necessária à binding executável:

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

Regras:

- root object com exatamente `manifest_version`, `package`, `source` e `destinations`;
- `manifest_version` exatamente `1`;
- `package.name`, `package.version` e todos os refs são UTF-8 não vazios, com no máximo
  255 caracteres;
- existe exatamente uma source e entre uma e 1.000 destinations;
- chaves duplicadas em qualquer objeto JSON são rejeitadas;
- refs são únicos no conjunto completo;
- a ordem de destinations é semântica e deve coincidir com
  `PackageVersionEndpoint.position`;
- unknown fields são rejeitados em todos os níveis;
- raw bytes, estrutura e parsing são bounded conforme a specification;
- o manifest não contém UUID, módulo, credential, config concreta ou raw secret.

ConnectorVersion, Operation e ContractVersion continuam pinados na projeção relacional. Eles
não são duplicados no JSON. A ligação ocorre por `PackageVersion.manifest_sha256` e pelo ref
local do endpoint: a projeção fornece os IDs autoritativos; a binding compilada fornece o
módulo.

SourceIdentity, config schema, Transformations, Enrichments, Interceptors, package
dependencies de domínio e metadata de distribuição ficam fora do Manifest v1. Adicioná-los
exige um formato posterior, sem reinterpretar manifests v1.

### Digest do manifest

`manifest_sha256` é o SHA-256 lowercase hexadecimal dos bytes exatos de `manifest.json`:

~~~elixir
manifest_sha256 =
  manifest_bytes
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16(case: :lower)
~~~

Não existe canonicalização de JSON, normalização de newline ou re-encoding antes do hash.
Qualquer mudança de bytes produz outra identidade de manifest.

O mesmo digest precisa coincidir em três lugares:

~~~text
PackageVersion.manifest_sha256
= packages/build.exs entry
= compiled binding manifest_sha256()
~~~

O digest identifica o manifest, não é assinatura, provenance ou prova criptográfica do
artefato BEAM. No primeiro caminho, o commit/release imutável pinna o código. Artifact hashing,
signing e remote distribution permanecem futuros.

### Compatibilidade do Catalog

`PackageVersion` ganha `manifest_sha256` imutável e globalmente único. A coluna física é
nullable somente para preservar rows históricas; toda nova publicação exige exatamente 64
caracteres lowercase hex.

PackageVersions históricas sem digest:

- permanecem legíveis;
- não são reescritas ou backfilled por inferência;
- são rejeitadas por novos deployments/replacements;
- são rejeitadas novamente pela resolução de uma nova Run;
- não selecionam fallback de módulo.

O erro público de `Deployments.create/1` e `Deployments.replace/2` é
`{:error, :package_not_bound}`. `Runs.create_from_deployment/1` preserva o envelope já
ratificado e devolve
`{:error, {:environment_deployment_not_executable, :package_not_bound}}`.

`RunSnapshot v1` continua contendo somente `package_version_id`. O digest é lido da
PackageVersion imutável quando o runtime resolve código; ele não é copiado para o snapshot.

### Binding compilada do package

Cada package expõe exatamente um módulo que usa o contract
`LeafcutterConnectors.Package`. Módulos são literais de código, nunca strings do manifest:

~~~elixir
defmodule ExampleSync.Package do
  use LeafcutterConnectors.Package,
    manifest: Path.expand("../../manifest.json", __DIR__),
    source: {"source", ExampleSync.Read},
    destinations: [{"destination", ExampleSync.Write}]
end
~~~

A macro lê e valida o arquivo durante a compilação, registra o caminho com
`@external_resource` e embute manifest e digest no BEAM. Os callbacks nunca leem filesystem em
runtime.

O passo 35 materializa funções puras para:

- devolver manifest validado e seu digest;
- devolver exatamente uma binding source;
- devolver destinations na ordem do manifest;
- resolver somente refs e roles declarados;
- rejeitar bindings extras, ausentes, duplicadas ou fora de ordem.

O módulo source precisa implementar `LeafcutterConnectors.Operation.Read`; cada destination
precisa implementar `LeafcutterConnectors.Operation.Write`. Conformance é verificada após a
compilação do package. Nenhum processo OTP por package ou Operation é criado.

O passo 35 está materializado em `leafcutter_connectors`: parsing bounded com rejeição de
UTF-8/chaves duplicadas, validação JSV + semântica complementar, digest dos bytes exatos e o
contract compilado com módulos literais, cobertura/ordem/role e `@external_resource`. O passo
37 materializa na inventory a prova de que o arquivo é o `manifest.json` raiz do próprio
package.

### Build inventory explícita

`packages/build.exs` é trusted build code versionado no repositório. Ele contém uma lista
literal; não executa glob nem descobre diretórios:

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

Cada entry exige exatamente `app`, `path`, `binding` e `manifest_sha256`. O build falha
para:

- key desconhecida;
- app, path, binding ou digest duplicado;
- path absoluto, path traversal (`..`), symlink cujo realpath escape `packages/` ou path
  inexistente;
- Mix project cujo `:app` diverge da entry;
- manifest ausente, inválido ou com digest diferente;
- binding compilada a partir de outro arquivo que não o `manifest.json` raiz do package;
- binding module ausente ou pertencente a outra OTP application;
- cobertura/role/order divergente;
- módulo de Operation sem o behaviour esperado.

A lista vazia é válida até 26C3. Um diretório sob `packages/` que não esteja no inventory não
entra no build, na release nem na resolução.

O passo 37 materializa o parser de literals e a validação em
`LeafcutterRuntime.PackageBuild`, carregada pela boundary Mix antes de derivar dependencies. A
inventory compilada repete as invariantes que dependem dos BEAMs prontos e é exposta por
`LeafcutterRuntime.ExecutablePackages.Inventory` sem leitura de filesystem em runtime. A
boundary exige dependency direta de `leafcutter_connectors` e rejeita dependencies para Core,
Runtime ou API no grafo Mix resolvido. A inventory de produção permanece `[]`; um Mix project
separado e `only: :test` fornece a prova de conformance.

### Dependency graph e release

Cada entry vira uma dependency Mix `:path` explícita de `leafcutter_runtime`. O package
pode depender somente de APIs públicas de `leafcutter_connectors` e de suas dependencies
próprias; não depende de Core, Runtime ou API.

~~~text
leafcutter_runtime
├── leafcutter_core
├── leafcutter_connectors
└── installed package
    └── leafcutter_connectors
~~~

Essa direção evita ciclo e faz o package entrar na dependency closure da release. O package é
uma OTP application sem supervisor próprio por default, não uma quinta platform application.

`mix quality` valida a inventory e executa format, compile, tests e Dialyzer dos packages
listados. Testes de dependencies não são assumidos como executados implicitamente pelo teste
da umbrella. A prova de release verifica que todos os `:app` da inventory pertencem à
application closure produzida.

O passo 37 materializa a release `:leafcutter` com `leafcutter_api` como entrypoint. A closure
transitiva inclui Core, Connectors, Runtime e todos os package apps derivados da inventory. O
gate usa a própria composição de `Mix.Release` para rejeitar apps ausentes; a fixture test-only
é `runtime: false` e não entra nessa closure.

### Resolução em runtime

`LeafcutterRuntime.ExecutablePackages.resolve/1` recebe um `PackageVersion.id` e:

1. lê a projeção por `Leafcutter.Catalog.Packages.get_version/1`;
2. rejeita PackageVersion sem `manifest_sha256`;
3. localiza a binding já compilada pelo digest;
4. compara name, version, source ref, destination refs, roles e ordem;
5. combina cada módulo com `operation_id` e `contract_version_id` autoritativos;
6. devolve uma binding in-memory completa e ordenada.

O retorno não é persistido nem serializado no RunSnapshot. Nenhum valor externo é convertido
em atom. O lookup por digest apenas escolhe entre módulos literais existentes na inventory.

Reasons esperados são allowlisted:

~~~elixir
@type resolve_error ::
        :package_version_not_found
        | :package_not_bound
        | :package_not_installed
        | :manifest_mismatch
        | :invalid_binding
~~~

Semântica estável:

- `:package_version_not_found`: o ID não existe;
- `:package_not_bound`: a row não possui digest válido;
- `:package_not_installed`: o digest válido não existe na inventory da release;
- `:manifest_mismatch`: name, version, refs, roles ou ordem divergem da projeção;
- `:invalid_binding`: o módulo literal não satisfaz o contract compilado.

Errors não carregam manifest raw, module name externo ou exception. Exceptions inesperadas de
package code permanecem defects visíveis.

### Semântica operacional

Uma PackageVersion pode existir no Catalog antes de estar presente numa release. Isso permite
publicação e rollout separados. A criação de nova Run falha antes de persistir Run/RunSnapshot
quando a release não contém o digest ou quando a projeção diverge.

`Runs.create_from_deployment/1` propaga os demais failures determinísticos de resolução no
mesmo envelope: `:package_not_installed`, `:manifest_mismatch` ou `:invalid_binding`. O reason
`:package_version_not_found` permanece exclusivo de `ExecutablePackages.resolve/1`, porque um
EnvironmentDeployment persistido mantém uma foreign key válida para PackageVersion.

Hot install, unload, code fetching e fallback para outra versão não existem no primeiro
caminho. Adicionar ou remover package exige novo build/release. Retenção de versões para Runs
ativas e rolling upgrade continuam decisões operacionais futuras.

## Alternativas rejeitadas

### Nome de módulo no manifest ou Catalog

Rejeitado porque transforma dado externo/persistido em identidade de VM, permite atom leaks e
acopla estado histórico a namespaces de código.

### Map de UUID para módulo

Rejeitado porque não é portável entre bancos, duplica a authority do PackageVersion e vira
registry manual sem contract de build.

### Filesystem ou BEAM behaviour discovery

Rejeitado porque torna a release dependente de ordem/ambiente e inclui código não revisado no
inventory explícito.

### Application config com módulos

Rejeitado porque separa a binding do dependency graph, permite drift por ambiente e não prova
que o package entrou na release.

### Persistir o inventory no RunSnapshot v1

Rejeitado porque módulos não são dados duráveis e porque a PackageVersion imutável já fornece
a referência necessária.

### Colocar todos os campos futuros no Manifest v1

Rejeitado porque SourceIdentity, Transformations, Enrichments e Interceptors ainda não possuem
um execution path completo. Congelá-los agora criaria contract especulativo.

## Sequência de materialização

~~~text
34. ratify Package Manifest/build binding/module resolution
35. manifest validation + Package binding contract (materializado)
36. PackageVersion manifest_sha256 + legacy enforcement (materializado)
37. explicit build inventory + Mix/release integration (materializado)
38. runtime resolution + Deployment/Run enforcement + quality gates (materializado)
~~~

Somente depois de 26C2 passar os gates o Slice 26C3 pode selecionar um sistema externo e
publicar a primeira Operation real.

## Consequências

- PackageVersion continua sendo a authority persistida;
- manifest e code binding são verificáveis sem UUIDs portáveis;
- módulos permanecem atoms literais em trusted build code;
- o mesmo manifest pode ser ligado a projections equivalentes em bancos diferentes;
- qualquer package novo exige mudança visível em `packages/build.exs`;
- `leafcutter_runtime` torna-se o composition root da binding;
- RunSnapshot v1 permanece estável;
- o primeiro package de produto continua fora do escopo.

## Evidência

- `apps/leafcutter_connectors/lib/leafcutter_connectors/package.ex`
- `apps/leafcutter_connectors/lib/leafcutter_connectors/package/manifest.ex`
- `apps/leafcutter_connectors/test/leafcutter_connectors/package_test.exs`
- `apps/leafcutter_connectors/test/leafcutter_connectors/package/manifest_test.exs`
- `apps/leafcutter_core/lib/leafcutter/catalog/schemas/package_version.ex`
- `apps/leafcutter_core/priv/repo/migrations/20260830070000_add_manifest_sha256_to_package_versions.exs`
- `apps/leafcutter_core/priv/repo/migrations/20260830071000_require_manifest_sha256_for_package_versions.exs`
- `apps/leafcutter_core/test/leafcutter/catalog/packages_test.exs`
- `packages/build.exs`
- `apps/leafcutter_runtime/mix.exs`
- `apps/leafcutter_runtime/mix/package_build.exs`
- `apps/leafcutter_runtime/lib/leafcutter_runtime/executable_packages/inventory.ex`
- `apps/leafcutter_runtime/lib/leafcutter_runtime/executable_packages.ex`
- `apps/leafcutter_runtime/lib/leafcutter_runtime/executable_packages/binding.ex`
- `apps/leafcutter_core/lib/leafcutter/integrations/deployments.ex`
- `apps/leafcutter_runtime/lib/leafcutter_runtime/runs.ex`
- `apps/leafcutter_runtime/test/leafcutter_runtime/executable_packages_test.exs`
- `apps/leafcutter_runtime/test/leafcutter_runtime/runs_resolution_test.exs`
- `apps/leafcutter_runtime/test/leafcutter_runtime/executable_packages/inventory_test.exs`
- `mix.exs`
- `docs/specifications/package-manifest-v1.md`
- `docs/decisions/ADR-0007-integration-packages.md`
- `docs/decisions/ADR-0022-transport-http-e-sequencia-26c.md`
- `docs/specifications/environment-deployment-run-resolution.md`
- `docs/specifications/run-snapshot-v1.md`
- Mix path dependencies: <https://hexdocs.pm/mix/Mix.Tasks.Deps.html>
- Mix releases: <https://hexdocs.pm/mix/Mix.Tasks.Release.html>
- Elixir configuration and releases: <https://hexdocs.pm/elixir/config-and-releases.html>
