# ContractVersion executável — specification

> **Status: MATERIALIZADO.**
>
> Owner: `Leafcutter.Catalog.Contracts` em `leafcutter_core`.
>
> Decisão: `docs/decisions/ADR-0019-contract-version-executavel-json-schema-jsv.md`.

## Objetivo

Materializar o menor slice que transforma uma `ContractVersion` nova em um documento JSON Schema Draft 2020-12 imutável, compilável e reutilizável para validação.

Ao concluir o slice:

~~~text
persisted ContractVersion
→ compile once
→ opaque Leafcutter validator
→ validate many JSON payloads
~~~

O slice completo também impede que novos PackageVersions, EnvironmentDeployments e Runs dependam de ContractVersions identity-only legadas.

## Estado de implementação

Estão materializados o documento persistido, a política e os limites, a publicação com build completo, `Contracts.compile/1`, `Contracts.validate/2` e a rejeição de legado em novas PackageVersions, novos ou substituídos EnvironmentDeployments e novas Runs resolvidas. RunSnapshot v1 permanece inalterado e todo estado histórico continua legível.

## Estado de entrada

Na `main` anterior ao slice:

- `ContractVersion` persiste somente `contract_id`, `version` e `published_at`;
- `Contracts.publish_version/2` ignora `schema`;
- `Packages.get_version/1` já preloads cada endpoint com `contract_version: :contract`;
- deployment create/replace e o resolver validam topologia, lifecycle e Connector, mas não executabilidade do contract;
- RunSnapshot v1 persiste somente `contract_version_id`.

Nenhum desses fatos deve ser descrito como já alterado até a implementação e os gates concluírem.

## Dependência

Adicionar em `leafcutter_core`:

~~~elixir
{:jsv, "~> 0.22.0"}
~~~

O lockfile deve resolver uma versão compatível da série 0.22.

## Modelo persistido

`ContractVersion` passa a expor:

~~~elixir
schema: map() | boolean() | nil
~~~

`nil` existe somente para linhas legadas. O changeset público de nova publicação nunca o aceita.

### Representação Ecto

Usar o tipo interno:

~~~elixir
Leafcutter.Catalog.Types.SchemaDocument
~~~

Contrato do tipo:

| Operação | Aceita | Rejeita |
|---|---|---|
| cast | map sem struct, `true`, `false` | list, string, number, `nil`, struct |
| dump | map sem struct, `true`, `false` | qualquer outra raiz |
| load | map, `true`, `false`, `nil` legado | qualquer outro valor persistido |

O tipo não envolve, converte ou normaliza a raiz.

### Migration

A migration deve:

1. adicionar `schema :jsonb` nullable e sem default;
2. adicionar CHECK para `NULL | object | boolean`;
3. instalar trigger que rejeita `schema IS NULL` em novos inserts;
4. preservar o trigger existente que rejeita update/delete.

A ordem precisa permitir upgrade de uma base que já contenha ContractVersions identity-only. Nenhuma linha existente é atualizada.

## Documento publicável

### Raiz

Aceitas:

~~~json
true
~~~

~~~json
false
~~~

~~~json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object"
}
~~~

Uma raiz object sem o `$schema` canônico ou com outro dialeto é inválida.

Rejeitadas como raiz:

~~~text
null
array
string
number
~~~

### Valores JSON

O walker de schema e o walker de payload aceitam recursivamente:

- map sem struct e somente com chaves string;
- list;
- string UTF-8 válida;
- integer ou float representável pelo encoder JSON;
- boolean;
- `nil`.

Eles rejeitam atom, tuple, PID, reference, function, struct, map com chave não string, string inválida e número que o encoder JSON não represente. A detecção retorna path determinístico e nunca inclui o valor inválido no erro público.

### Referências

Valores de `$ref` e `$dynamicRef` devem ser strings fragment-only:

~~~text
#
#/$defs/customer
#customer
~~~

São inválidos:

~~~text
schema.json
schema.json#/$defs/customer
../schema.json
https://example.test/schema
jsv:module:Elixir.SomeSchema
~~~

O walker verifica essas keywords em qualquer profundidade. A validação de sintaxe e resolução do fragment também precisa ser concluída pelo build do JSV.

### Extensões

`jsv-cast` e `x-jsv-cast` são rejeitadas em qualquer profundidade. Keywords desconhecidas que não executem código permanecem permitidas conforme Draft 2020-12.

Não configurar:

- resolver HTTP ou filesystem;
- custom formats;
- custom vocabularies;
- module schema input;
- cast functions;
- default application.

### Limites

| Limite | Valor | Contagem |
|---|---:|---|
| JSON serializado | 1.048.576 bytes | representação UTF-8 sem envelope |
| profundidade | 64 | raiz = 1; cada container aninhado incrementa |
| nós | 10.000 | raiz e cada valor; object keys não contam |

Todos os limites são verificados antes de construir a root do JSV.

## Publicação

Assinatura:

~~~elixir
Contracts.publish_version(contract_id, %{
  version: version,
  schema: schema_document
})
~~~

Chaves string continuam aceitas na mesma boundary.

Pipeline obrigatório:

~~~text
fetch Contract
→ build publication changeset
→ validate JSON/root/dialect/refs/extensions/limits
→ validate Draft 2020-12 schema
→ JSV.build with fixed options
→ insert immutable ContractVersion
~~~

Opções equivalentes exigidas no build:

~~~elixir
default_meta: "https://json-schema.org/draft/2020-12/schema",
formats: true,
atoms: false,
vocabularies: %{}
~~~

Não usar `build!` na boundary pública. Falha de schema ou build produz erro no campo `schema` do changeset. Não persistir parcialmente nem expor exception do JSV.

Retornos permanecem:

~~~elixir
{:ok, ContractVersion.t()}
{:error, :contract_not_found}
{:error, Ecto.Changeset.t()}
~~~

## Compilação

Assinatura:

~~~elixir
Contracts.compile(contract_version_id)
~~~

Contrato:

~~~elixir
{:ok, Contracts.validator()}
| {:error, :not_found}
| {:error, :schema_unavailable}
| {:error, :schema_compilation_failed}
~~~

Regras:

- busca exatamente uma `ContractVersion`;
- versão ausente retorna `:not_found`;
- versão legada com `schema: nil` retorna `:schema_unavailable`;
- JSON, dialeto, refs, extensões e limites são rechecados antes do JSV;
- schema persistido que não constrói retorna `:schema_compilation_failed`;
- sucesso devolve wrapper opaco contendo o ID e a root JSV;
- o caller não recebe nem depende de `JSV.Root`;
- cada chamada compila no máximo uma vez;
- não existe cache global ou processo.

## Validação

Assinatura:

~~~elixir
Contracts.validate(validator, payload)
~~~

Contrato de sucesso:

~~~elixir
{:ok, payload}
~~~

O termo retornado é o payload original recebido pelo Leafcutter. O retorno transformado do JSV é descartado mesmo quando o JSV normaliza uma representação numérica.

Invocação JSV equivalente:

~~~elixir
JSV.validate(payload, root, cast: false, cast_formats: false)
~~~

Contrato de erro:

~~~elixir
{:error,
 %Contracts.ValidationError{
   contract_version_id: contract_version_id,
   reason: :invalid_json | :schema_violation,
   details: normalized_details
 }}
~~~

`:invalid_json` é decidido antes do JSV. `:schema_violation` representa falha contra uma root válida.

`normalized_details`:

- é composto somente por values JSON;
- usa chaves string;
- mantém instance, schema e evaluation paths úteis;
- mantém keyword/kind útil;
- é ordenado ascendentemente e de forma estável;
- omite messages ou campos que incorporem payload values;
- não contém schema bruto, validator, exception ou struct do JSV.

A shape pública deve ser produzida por código do Leafcutter a partir do erro JSV normalizado com string keys; não retornar diretamente o struct ou map completo da biblioteca.

`validate/2` não usa Repo, não resolve refs, não recompila e não executa efeitos externos.

## Executabilidade e legado

Uma `ContractVersion` é executável se e somente se seu `schema` persistido não é `nil`. A publicação comprova validade e compilação; as boundaries posteriores não repetem o build.

| Estado | Leitura histórica | Novo PackageVersion | Novo/replace deployment | Nova Run por deployment |
|---|---|---|---|---|
| schema válido | permitida | permitida | permitida | permitida |
| `schema: nil` legado | permitida | rejeitada | rejeitada | rejeitada |

### PackageVersion

`Packages.publish_version/2` deve verificar cada `contract_version_id` antes de selar a versão. Uma referência legada adiciona erro ao campo `contract_version_id` do endpoint changeset e a transação inteira faz rollback.

Não criar PackageVersion parcialmente publicada nem alterar PackageVersions existentes.

### EnvironmentDeployment

`Deployments.create/1` e `replace/2` usam a projeção já retornada por `Packages.get_version/1`.

Se qualquer endpoint tiver `schema: nil`, retornam:

~~~elixir
{:error, {:contract_versions_not_executable, sorted_contract_version_ids}}
~~~

IDs são únicos e ordenados. Nenhum deployment ou replacement parcial cruza a transaction boundary.

### Resolver

`LeafcutterRuntime.Runs.create_from_deployment/1` repete a verificação depois de carregar a PackageVersion na transação de resolução e antes de construir a definition:

~~~elixir
{:error,
 {:environment_deployment_not_executable,
  {:contract_versions_not_executable, sorted_contract_version_ids}}}
~~~

Nenhuma Run ou RunSnapshot é persistida no erro.

## RunSnapshot

Não alterar:

- `RunSnapshot.current_format_version/0`;
- `RunSnapshot.DefinitionV1`;
- schema físico de `run_snapshots`;
- `Executions.Runs.create/1`;
- JSON persistido da definition.

O snapshot continua contendo somente:

~~~text
source.contract_version_id
destinations[].contract_version_id
~~~

Schema e validator são carregados posteriormente por ID e nunca copiados para o snapshot.

## Matriz mínima de testes

### Tipo e persistência

- cast/dump/load de object, `true` e `false`;
- round-trip real pelo PostgreSQL para as três raízes;
- rejeição de array, string, number, struct e `nil` novo;
- CHECK de root type;
- trigger de schema obrigatório em insert;
- update/delete continuam rejeitados;
- uma linha legada pré-migration permanece `schema: nil`.

### Publicação

- schema obrigatório com attrs atom e string;
- object com dialeto canônico;
- boolean `true` e `false`;
- schema sintaticamente ou semanticamente inválido;
- dialeto ausente ou diferente;
- local refs e local dynamic refs válidos;
- refs relativas, remotas e `jsv:module:` inválidas;
- `jsv-cast` e `x-jsv-cast` em qualquer profundidade;
- custom format input não amplia os formats configurados;
- limites imediatamente abaixo/no/acima das boundaries;
- rollback total em qualquer erro.

### Compile e validate

- `:not_found`, `:schema_unavailable` e `:schema_compilation_failed`;
- validator opaco sem vazamento de JSV;
- validações repetidas reutilizam a mesma root;
- `true` aceita todo payload JSON e `false` produz schema violation;
- payloads JSON escalares e compostos;
- payload Elixir inválido com path determinístico;
- sucesso retorna exatamente o payload original;
- schema violation normalizada e ordenada;
- details não contêm payload values nem structs/exceptions;
- nenhum Repo call ou rebuild em `validate/2`.

### Propagação

- PackageVersion rejeita uma ou várias versões legadas atomicamente;
- deployment create e replace retornam IDs únicos ordenados;
- resolver retorna o erro envelopado e não cria Run;
- estado histórico permanece legível;
- RunSnapshot v1 permanece byte-shape compatible.

## Fora de escopo

- behaviours/result structs de Operation;
- Transport behaviour;
- HTTP client, pool, request ou pagination;
- escolha source/destination de qual payload validar;
- compile no `RunCoordinator`;
- cache compartilhado;
- referências externas;
- schema registry;
- endpoint público de upload;
- payload/body/batch/throughput limits;
- Task timeout, sandbox ou isolamento;
- RunSnapshot v2;
- data plane.

Esses itens pertencem aos slices 26B, 26C ou posteriores e não devem entrar por conveniência durante 26A.
