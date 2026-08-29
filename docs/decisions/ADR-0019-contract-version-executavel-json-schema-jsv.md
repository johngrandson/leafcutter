# ADR-0019 — ContractVersion executável com JSON Schema/JSV

- Status: Accepted
- Estado de implementação: MATERIALIZADO
- Data: 2026-08-29

## Contexto

O ADR-0006 escolheu JSON Schema Draft 2020-12 e JSV para os contracts externos. O ADR-0018 materializou `Contract` e `ContractVersion` somente como authorities de identidade imutáveis, suficientes para congelar referências em RunSnapshot v1, mas ainda sem definição executável.

O menor próximo slice precisa tornar uma `ContractVersion` publicável, compilável e reutilizável para validação sem antecipar os behaviours de Operation, o Transport HTTP ou o data plane. Ele também precisa preservar as versões identity-only já persistidas e manter RunSnapshot v1 estável.

## Estado materializado

A representação Ecto, a política de documento, o build JSV interno, a persistência nullable compatível com legado, a publicação schema-aware, a compilação pública, a validação de payload e a rejeição de ContractVersions legadas nas boundaries de PackageVersion, EnvironmentDeployment e resolução de Run estão materializados.

`LeafcutterRuntime.Runs.create_from_deployment/1` devolve o erro envelopado ratificado antes de criar Run ou RunSnapshot. RunSnapshot v1 permanece inalterado.

## Decisão

### Escopo e ownership

O slice 26A pertence a `Leafcutter.Catalog.Contracts`, em `leafcutter_core`.

O escopo ratificado compreende:

- schema imutável em `ContractVersion`;
- validação e compilação no instante da publicação;
- compilação explícita de uma versão persistida;
- validação de payload com validator reutilizável;
- rejeição de versões legadas nas novas boundaries executáveis já existentes.

Connector/Operation executáveis, Transport HTTP, carregamento pelo `RunCoordinator`, payload body limits e execução Broadway permanecem fora deste slice.

### Persistência e compatibilidade com legado

`contract_versions` receberá uma única coluna `schema jsonb`, sem envelope e sem normalização. Um schema booleano permanece `true` ou `false` no banco; não será convertido em objeto.

A migration preservará linhas existentes com `schema IS NULL`. Essas versões continuam legíveis, referenciáveis por estado histórico e imutáveis, mas não são executáveis.

Toda nova `ContractVersion` deverá nascer com schema no mesmo insert da publicação. Não haverá backfill com `true`, attach posterior, update, replace ou republicação do mesmo registro. Tornar um contract legado executável exige publicar uma nova `ContractVersion`.

Proteções no PostgreSQL:

~~~sql
CHECK (
  schema IS NULL
  OR jsonb_typeof(schema) IN ('object', 'boolean')
)
~~~

Um trigger de insert rejeitará novas linhas com `schema IS NULL`. O trigger de imutabilidade já existente continuará rejeitando update e delete.

Como `field :schema, :map` não representa raízes booleanas e `:any` não é um tipo persistível, o schema usará o tipo Ecto interno `Leafcutter.Catalog.Types.SchemaDocument`. Esse tipo aceitará somente raiz object ou boolean e preservará o valor JSONB sem envelope.

### Dialeto e documento aceito

O dialeto é fixo:

~~~text
https://json-schema.org/draft/2020-12/schema
~~~

Uma raiz object deve declarar exatamente esse valor em `$schema`. Uma raiz booleana usa o mesmo dialeto fixo por definição do Leafcutter.

O documento inteiro deve conter somente valores JSON legítimos: maps sem struct e com chaves string, lists, strings UTF-8 válidas, números representáveis em JSON, booleans e `nil`.

`$ref` e `$dynamicRef` podem apontar somente para fragments do próprio documento. Referências relativas, absolutas, remotas e `jsv:module:` são rejeitadas antes do build. O slice não instala resolver de rede nem lê schema do filesystem.

Keywords desconhecidas continuam seguindo a semântica do Draft 2020-12. As extensões executáveis do JSV `jsv-cast` e `x-jsv-cast` são proibidas em qualquer profundidade. Não haverá custom vocabularies, custom formats, criação de atoms, casting nem aplicação de defaults.

Uma futura adoção de referências externas deverá primeiro resolver e empacotar todo o grafo em um documento autocontido, imutável e sujeito aos mesmos limites antes da publicação.

### Publicação

A aridade permanece:

~~~elixir
Leafcutter.Catalog.Contracts.publish_version(contract_id, attrs)
~~~

`attrs` passa a exigir `version` e `schema`. Antes do insert, a boundary:

1. valida a representação JSON;
2. valida raiz, dialeto, referências e extensões proibidas;
3. aplica limites de tamanho e estrutura;
4. comprova o schema contra Draft 2020-12;
5. conclui um build completo do JSV.

O build usa JSV `~> 0.22.0`, formats padrão habilitados, atoms desabilitados e nenhum formato ou vocabulary customizado.

Qualquer falha adiciona erro ao campo `schema` do changeset e nenhuma linha é persistida. `:contract_not_found` e o contrato geral de retorno de `publish_version/2` permanecem.

### Compilação e reutilização

A API pública será:

~~~elixir
Leafcutter.Catalog.Contracts.compile(contract_version_id)
~~~

Retornos:

~~~elixir
{:ok, validator}
{:error, :not_found}
{:error, :schema_unavailable}
{:error, :schema_compilation_failed}
~~~

`validator` é um valor opaco do Leafcutter que retém a identidade da `ContractVersion` e a root construída pelo JSV. O tipo concreto do JSV não cruza a boundary pública.

`compile/1` lê a versão persistida e compila uma vez por chamada. `:schema_unavailable` identifica uma versão legada com `schema: nil`. `:schema_compilation_failed` protege a boundary caso um estado persistido inválido exista apesar das invariantes de publicação.

Antes de invocar o JSV, `compile/1` reaplica a política de documento, referências, extensões e limites. Assim, até um estado inserido fora da API pública não consegue acionar o resolver interno `jsv:module:` nem introduzir resolução externa.

Não haverá ETS, GenServer, cache global nem processo dedicado. O futuro processo de uma Run compilará cada contract necessário uma vez no startup e manterá os validators em seu próprio estado.

### Validação de payload

A API pública será:

~~~elixir
Leafcutter.Catalog.Contracts.validate(validator, payload)
~~~

`validate/2`:

- não acessa Repo, rede ou filesystem;
- não recompila o schema;
- aceita somente payload composto por valores JSON legítimos;
- executa o JSV sem generic casts e sem format casts;
- em sucesso, retorna o payload original, não o valor eventualmente normalizado pelo JSV.

Retornos:

~~~elixir
{:ok, original_payload}

{:error,
 %Leafcutter.Catalog.Contracts.ValidationError{
   contract_version_id: contract_version_id,
   reason: :invalid_json | :schema_violation,
   details: normalized_details
 }}
~~~

`normalized_details` deve ser JSON-compatible e determinístico, com paths e keywords ordenados. Ele não pode conter payload values, structs/exceptions do JSV nem a root compilada. A representação é propriedade do Leafcutter.

### Limites e trust boundary

A publicação inicial é uma operação administrativa confiável; este ADR não cria endpoint público para upload arbitrário.

Limites por documento:

- tamanho JSON serializado máximo: 1 MiB;
- profundidade estrutural máxima: 64;
- quantidade máxima de nós JSON: 10.000.

A raiz conta como profundidade 1 e como um nó. Cada valor de object ou elemento de array acrescenta um nó; chaves de object não contam separadamente.

O slice usa a proteção limitada de regex disponível no JSV 0.22 e não adiciona Task timeout, sandbox, processo OTP ou isolamento de package. Limites de payload, body, batch e throughput serão decididos junto ao primeiro execution path.

### Propagação pelas boundaries existentes

Novos writes não podem criar estado que dependa de uma `ContractVersion` legada:

- `Catalog.Packages.publish_version/2` rejeita endpoints que referenciem versão sem schema, usando erro de changeset em `contract_version_id`;
- `Integrations.Deployments.create/1` e `replace/2` rejeitam uma `PackageVersion` que contenha contract versions não executáveis;
- `LeafcutterRuntime.Runs.create_from_deployment/1` repete a verificação na boundary final de resolução.

Quando aplicável, os IDs não executáveis são únicos e ordenados. O resolver retorna:

~~~elixir
{:error,
 {:environment_deployment_not_executable,
  {:contract_versions_not_executable, sorted_contract_version_ids}}}
~~~

`Catalog.Packages.get_version/1` já carrega endpoints com `contract_version: :contract`; não será criada uma capability pública apenas para essa checagem.

Estado histórico não é reescrito: PackageVersions, EnvironmentDeployments, Runs e RunSnapshots existentes permanecem legíveis. Os writes e as novas resoluções é que aplicam a regra.

### RunSnapshot v1

RunSnapshot v1 não muda e não haverá format v2 neste slice. A definition continua congelando somente o `contract_version_id` imutável de cada endpoint.

`Leafcutter.Executions.Runs.create/1` continua validando somente a estrutura da definition. A executabilidade pertence ao resolver upstream e, futuramente, ao startup do runtime. Schema bruto e validator compilado nunca são persistidos no snapshot.

## Consequências

- uma versão publicada nova é autossuficiente e comprovadamente compilável;
- versões legadas continuam históricas sem ganhar semântica falsa;
- schema e dependência JSV permanecem owned pelo Catalog;
- a validação é reutilizável sem cache global prematuro;
- nenhum acesso externo pode ocorrer durante compile ou validate;
- o contrato público não fica acoplado aos structs e mensagens do JSV;
- object e boolean schemas têm round-trip físico fiel no mesmo campo JSONB;
- PackageVersion, deployment e resolver impedem novas Runs baseadas em contratos identity-only;
- Operation/Transport podem ser ratificados depois sobre uma boundary de contract já executável.

## Provas exigidas na materialização

A specification relacionada define a matriz detalhada. A materialização completa prova:

- round-trip de object, `true` e `false` pelo Ecto type e PostgreSQL;
- preservação de linha legada com `schema: nil`;
- rejeição física de nova linha sem schema e de raízes array/string/number;
- publicação atômica e build completo;
- dialeto, referências, extensões e limites;
- compile sem vazamento de JSV;
- validate sem Repo/rebuild/casting e retornando o payload original;
- erros normalizados, ordenados e sem payload values;
- rejeições em PackageVersion, EnvironmentDeployment e resolver;
- ausência de mudança no formato RunSnapshot v1.

## Relação com decisões anteriores

Este ADR detalha e materializa o próximo contrato decisório do ADR-0006 sem reescrevê-lo. Ele evolui a `ContractVersion` identity-only introduzida pelo ADR-0018 e preserva integralmente o ADR-0017.

## Referências

- [JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12/schema)
- [JSV 0.22.0](https://jsv.hexdocs.pm/JSV.html)
- [JSV changelog](https://hex.pm/packages/jsv/0.22.0/files/CHANGELOG.md)
- [JSV resolver interno](https://jsv.hexdocs.pm/JSV.Resolver.Internal.html)
- [JSV error formatter](https://jsv.hexdocs.pm/JSV.ErrorFormatter.html)
- [Ecto custom types](https://hexdocs.pm/ecto/Ecto.Type.html)
- [PostgreSQL JSON types](https://www.postgresql.org/docs/current/datatype-json.html)
