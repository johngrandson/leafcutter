# Contracts e JSON Schema

> **Status: MATERIALIZADO — SLICE 26A CONCLUÍDO.**
>
> ADRs canônicos: ADR-0006 e ADR-0019.

## Estado atual na main

O Catalog materializa:

~~~text
Contract
└── ContractVersion executable
    └── immutable schema JSONB
~~~

`Leafcutter.Catalog.Contracts` expõe `create/1`, `get/1`, `publish_version/2`, `compile/1` e `validate/2`. Novas versões exigem schema object ou boolean, validado e construído com JSV antes do insert; o PostgreSQL preserva schema nullable para rows legadas, rejeita novos inserts sem schema e impede update/delete.

O código atual:

- preserva ContractVersions identity-only legadas como históricas e não executáveis;
- compila um validator Leafcutter opaco por chamada;
- valida payload JSON sem Repo, rebuild ou casting;
- rejeita novas PackageVersions e novos EnvironmentDeployments que referenciem ContractVersion legada;
- revalida todas as ContractVersions na resolução de uma nova Run.

As proteções em EnvironmentDeployment create/replace e na resolução de Run estão materializadas. RunSnapshot v1 congela somente `contract_version_id` e permanece inalterado.

## Slice 26A

O ADR-0019 torna cada nova `ContractVersion` um documento JSON Schema Draft 2020-12 executável:

~~~text
ContractVersion
├── immutable identity/version
└── immutable schema JSONB
    → validated and built on publication
    → compiled explicitly
    → reused for payload validation
~~~

Representação:

- uma coluna `schema jsonb`, sem envelope;
- raiz object ou boolean;
- object exige `$schema: https://json-schema.org/draft/2020-12/schema`;
- boolean usa o dialeto fixo do Leafcutter;
- versões existentes permanecem `schema: nil`, históricas e não executáveis;
- novas versões exigem schema no insert;
- object, `true` e `false` preservam round-trip físico.

Política de resolução:

- somente `$ref` e `$dynamicRef` fragment-only no mesmo documento;
- nenhuma rede ou filesystem;
- referências relativas, remotas e `jsv:module:` proibidas;
- `jsv-cast` e `x-jsv-cast` proibidas;
- custom formats/vocabularies, atoms, casting e defaults não entram.

Publicação:

~~~text
validate JSON shape and limits
→ validate fixed dialect and reference policy
→ validate schema
→ complete JSV build
→ immutable insert
~~~

Falhas aparecem como changeset error no campo `schema` e não persistem linha parcial.

APIs ratificadas:

~~~elixir
Leafcutter.Catalog.Contracts.compile(contract_version_id)
Leafcutter.Catalog.Contracts.validate(validator, payload)
~~~

`compile/1` devolve um validator Leafcutter opaco. `validate/2` reutiliza a root, não acessa Repo ou rede e retorna o payload original em sucesso.

Não haverá cache global inicial. O futuro processo de Run manterá os validators compilados em seu próprio estado.

## Executabilidade nas boundaries

O schema permanece owned pelo Catalog e não é copiado para PackageVersion, EnvironmentDeployment ou RunSnapshot.

Novos writes aplicam:

~~~text
PackageVersion publication (materializado)
→ rejects legacy ContractVersion

EnvironmentDeployment create/replace (materializado)
→ rejects PackageVersion with legacy ContractVersion

EnvironmentDeployment → Run resolver (materializado)
→ rechecks all final ContractVersion IDs
~~~

O resolver usa:

~~~elixir
{:error,
 {:environment_deployment_not_executable,
  {:contract_versions_not_executable, sorted_contract_version_ids}}}
~~~

Estado histórico não é reescrito. A regra protege apenas novas publicações, novos deployments/replacements e novas resoluções.

## Limites ratificados

- schema serializado: 1 MiB;
- profundidade estrutural: 64;
- nós JSON: 10.000;
- JSV `~> 0.22.0`;
- formats padrão habilitados;
- atoms desabilitados;
- proteção limitada de regex do JSV;
- nenhum Task timeout, sandbox ou processo OTP no primeiro slice.

O ADR-0022 ratifica um cap obrigatório e um hard maximum central para o response body raw do Transport. Request payload, decoded payload e batch limits gerais permanecem para o primeiro execution path que os utilizar.

## Separação dos próximos slices

~~~text
26A ContractVersion executable
→ JSON Schema/JSV boundary

26B Operation executable
→ behaviours, invocation and result contracts

26C1 HTTP Transport boundary
→ bounded one-attempt Finch adapter

26C2 executable package binding + module resolution (parcial; passos 35–36 materializados)

26C3 first reference Operation (aberto)
~~~

O ADR-0021 ratifica os pontos source/destination de validação, paginação opaca e partial
success. O client/pool HTTP de 26C1 está materializado conforme o ADR-0022. Os passos 35–36 do
Package Manifest/module resolution estão materializados conforme o ADR-0023; inventory/release
e resolução em runtime permanecem nos passos 37–38. Referência real e data plane continuam
posteriores.

## Especificação próxima do código

Detalhes de tipos, pipeline, retornos, compatibilidade legada e matriz de testes:

`docs/specifications/contract-version-execution.md`.
