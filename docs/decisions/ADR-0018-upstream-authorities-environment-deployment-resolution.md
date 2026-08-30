# ADR-0018 — Authorities upstream mínimas e resolução de EnvironmentDeployment

- Status: Accepted
- Estado de implementação: MATERIALIZADO
- Data: 2026-08-28

## Contexto

RunSnapshot v1 já materializa o destino estrutural, versionado e imutável de uma resolução executável. A próxima fronteira precisa persistir as authorities mínimas de Catalog, Connections e Integrations e compô-las em `leafcutter_runtime` sem antecipar Package Manifest, data plane ou secrets concretos.

Os schemas, APIs e a semântica do resolver foram ratificados neste ADR e na specification relacionada. Catalog, Connections, Integration, EnvironmentDeployment, seus bindings e o resolver transacional foram materializados em sub-slices ordenados.

## Decisão

### Topologia interna de PackageVersion

`PackageVersion` exporá sua topologia executável por uma projeção relacional interna:

```text
PackageVersion
└── PackageVersionEndpoint
    ├── ref
    ├── role: source | destination
    ├── position
    ├── operation_id
    └── contract_version_id
```

Regras aprovadas:

- uma PackageVersion possui exatamente uma source e uma ou mais destinations;
- `ref` é local à PackageVersion e único entre source e destinations;
- `position` preserva a ordem declarada das destinations sem definir prioridade de execução;
- `Operation` permanece pertencente a uma `ConnectorVersion`, portanto o endpoint não duplica `connector_version_id`;
- `ContractVersion` é referenciada explicitamente pelo endpoint;
- a projeção é um contract interno do Catalog e não ratifica field names do Package Manifest v1;
- a futura ingestão de packages será responsável por materializar essa projeção a partir de um manifest validado.

## Modelo mínimo do Catalog

O primeiro slice materializará:

```text
Catalog
├── Connector
│   └── ConnectorVersion
│       └── Operation
├── Contract
│   └── ContractVersion
└── Package
    └── PackageVersion
        └── PackageVersionEndpoint
```

Regras aprovadas:

- `Connector`, `Contract` e `Package` são identidades globais estáveis e não possuem tenancy;
- cada versão possui UUID e uma string `version` opaca, única dentro da identidade pai;
- Semantic Versioning não é validado neste slice;
- versões nascem publicadas e seu conteúdo é imutável;
- não existem draft, update, delete, deprecation ou availability lifecycle inicialmente;
- `ConnectorVersion` e suas Operations são publicadas atomicamente;
- cada Operation possui `ref` e `role: source | destination`;
- `ContractVersion` materializa somente a authority de identidade necessária para a resolução; JSON Schema e JSV permanecem para o estágio posterior;
- `PackageVersion` e seus endpoints são publicados atomicamente;
- o PostgreSQL rejeita alterações no conteúdo versionado;
- metadata mutável de disponibilidade permanece para um slice futuro.

APIs públicas serão organizadas por capacidades reais:

```text
Leafcutter.Catalog.Connectors
Leafcutter.Catalog.Contracts
Leafcutter.Catalog.Packages
```

## Modelo mínimo de Connections

O primeiro slice materializará:

```text
Environment
├── Connection
│   └── optional current SecretVersion binding
└── Secret
    └── immutable SecretVersion
```

Persistência mínima:

```text
Connection
├── id
├── organization_id
├── environment_id
├── connector_id
├── name
├── config
├── secret_version_id | null
└── disabled_at

Secret
├── id
├── organization_id
├── environment_id
└── name

SecretVersion
├── id
├── secret_id
└── version
```

Regras aprovadas:

- Connection, Secret e SecretVersion são environment-scoped, com Organization e Environment explícitos;
- o PostgreSQL impede associação entre Organization e Environment incompatíveis;
- Connection referencia a identidade estável de Connector, nunca ConnectorVersion;
- `config` é um JSON object não sensível;
- `secret_version_id` é opcional e representa o binding exato atualmente selecionado;
- SecretVersion é imutável e sua versão é única dentro de Secret;
- nenhum raw secret, ciphertext, provider locator ou credential é persistido neste slice;
- Connection pode alterar config ou SecretVersion; mudanças afetam somente resoluções futuras;
- snapshots existentes preservam a config e o SecretVersion anteriores;
- Connection desabilitada não pode participar de novas resoluções;
- Organization ou Environment desabilitado bloqueia criação, alteração e resolução;
- não existe seleção implícita da última SecretVersion;
- revogação, rotação, exclusão e retenção continuam abertas.

APIs públicas:

```text
Leafcutter.Connections
├── create/1
├── get/1
├── update/2
└── disable/1

Leafcutter.Connections.Secrets
├── create/1
└── create_version/1
```

## Modelo mínimo de Integrations

O primeiro slice materializará:

```text
Organization
└── Integration
    └── EnvironmentDeployment
        └── EnvironmentDeploymentBinding
```

Persistência mínima:

```text
Integration
├── id
├── organization_id
├── package_id
├── name
└── disabled_at

EnvironmentDeployment
├── id
├── organization_id
├── environment_id
├── integration_id
├── package_version_id
├── promotable_config
└── local_config

EnvironmentDeploymentBinding
├── environment_deployment_id
├── ref
└── connection_id
```

Regras aprovadas:

- Integration é organization-scoped e referencia a identidade estável de Package;
- uma Integration não troca de Package;
- existe no máximo um EnvironmentDeployment por Integration e Environment;
- o deployment representa o estado executável atual e é mutável;
- alterações substituem atomicamente PackageVersion, configs e o conjunto completo de bindings;
- não existem revision, history, draft, promotion ou rollback neste slice;
- promotable config e local config permanecem separados e não sensíveis;
- effective config é calculada pelo resolver e não é persistida no deployment;
- bindings armazenam somente o ref do endpoint e a Connection;
- role, posição, Operation e ContractVersion continuam vindo da PackageVersion;
- o binding não armazena SecretVersion; o resolver congela o binding atual da Connection;
- create e replace validam compatibilidade semântica naquele momento;
- o resolver repete a validação ao criar uma Run porque Connection e deployment são mutáveis;
- Integration desabilitada bloqueia todos os seus deployments;
- EnvironmentDeployment não possui lifecycle independente inicialmente: existe completo ou não existe.

Validações de create e replace:

```text
PackageVersion belongs to the Integration Package
bindings match all PackageVersion endpoints exactly
Connections belong to the same Environment
Connection Connector is compatible with the endpoint Operation
Organization, Environment, Integration and Connections are active
```

APIs públicas:

```text
Leafcutter.Integrations
├── create/1
├── get/1
└── disable/1

Leafcutter.Integrations.Deployments
├── create/1
├── get/1
├── fetch_resolution_scope/1
├── replace/2
└── lock_for_resolution/1
```

## Merge de configuração efetiva

`effective_config` é derivada em memória e nunca persistida no EnvironmentDeployment:

```text
promotable_config
        ↓
recursive merge
        ↑
local_config wins
        ↓
effective_config
```

Regras aprovadas:

- promotable config e local config são JSON objects;
- o merge é determinístico e recursivo;
- quando ambos os valores são objects, suas chaves são combinadas recursivamente;
- em qualquer outro conflito, o valor local substitui integralmente o valor promovível;
- arrays são substituídos e nunca concatenados;
- `null` é um valor explícito de override e não significa remoção;
- chaves presentes somente em um dos lados são preservadas;
- Connection config não participa desse merge e é congelada separadamente por endpoint;
- SecretVersion nunca participa de config;
- Package defaults não entram neste slice;
- RunSnapshot persiste somente effective config;
- a provenance continua representada pelos dois campos separados no EnvironmentDeployment.

Essa precedência preserva a promoção futura: somente promotable config será copiada, enquanto cada Environment manterá sua local config.

## Boundary transacional do resolver

A API de orchestration será:

```elixir
LeafcutterRuntime.Runs.create_from_deployment(environment_deployment_id)
```

O workflow permanece no módulo público de Runs já existente em `leafcutter_runtime`. Não será criada service layer, processo OTP ou workflow abstraction adicional.

Fluxo aprovado:

```text
create_from_deployment
→ one shared Repo transaction
→ discover immutable deployment parent IDs through a public API
→ lock mutable authorities through public context APIs
→ fetch immutable Catalog and SecretVersion projections
→ validate semantic consistency
→ build definition v1
→ Executions.Runs.create/1 inside the same transaction
→ commit Run + RunSnapshot
```

Antes dos locks, `Deployments.fetch_resolution_scope/1` lê somente os IDs imutáveis de Organization, Environment e Integration. Essa descoberta não lê bindings, PackageVersion ou config, não valida executabilidade e não constitui a leitura autoritativa do estado do deployment.

Ordem fixa dos locks e das leituras autoritativas:

```text
1. Organization
2. Environment
3. Integration
4. EnvironmentDeployment
5. Connection rows ordered by ID
6. immutable Catalog projection
7. immutable SecretVersion identities
```

Regras aprovadas:

- leafcutter_runtime abre uma única transação externa no Repo compartilhado;
- contexts são acessados somente por APIs públicas;
- a descoberta preliminar permanece dentro da mesma transação e retorna somente identidade imutável;
- Organization, Environment, Integration, deployment e Connections recebem locks de leitura que bloqueiam alterações concorrentes;
- PackageVersion, endpoints, Operations, ContractVersions e SecretVersions não precisam de lock porque são imutáveis;
- o deployment é bloqueado antes da leitura de seus bindings;
- Connections são bloqueadas em ordem de ID;
- nenhum HTTP, PubSub, Oban ou efeito externo ocorre dentro da transação;
- replace, update ou disable concorrente espera a resolução terminar;
- o resolver repete as validações semânticas e calcula effective config;
- `Executions.Runs.create/1` participa da mesma transação;
- qualquer erro semântico ou changeset inválido causa rollback integral;
- sucesso retorna uma Run `pending`;
- o workflow não inicia a árvore local;
- RunRecovery continua responsável por claim e startup;
- o formato v1 permanece sem Organization, Environment, Integration ou Deployment IDs.

## Contrato público e erros

A API retorna:

```elixir
@spec create_from_deployment(EnvironmentDeployment.id()) ::
        {:ok, Run.t()}
        | {:error, create_from_deployment_error()}
```

Tipos ratificados:

```elixir
@type create_from_deployment_error ::
        :environment_deployment_not_found
        | {:environment_deployment_not_executable,
           deployment_not_executable_reason()}
        | Ecto.Changeset.t()

@type deployment_not_executable_reason ::
        :organization_disabled
        | :environment_disabled
        | :integration_disabled
        | :package_version_mismatch
        | {:binding_mismatch,
           %{
             missing_refs: [String.t()],
             unexpected_refs: [String.t()]
           }}
        | {:connection_not_found, Connection.id()}
        | {:connection_disabled, Connection.id()}
        | {:connection_scope_mismatch, Connection.id()}
        | {:connector_mismatch, String.t()}
        | {:secret_version_not_found, SecretVersion.id()}
        | {:secret_version_scope_mismatch, SecretVersion.id()}
```

Regras aprovadas:

- refs em erros são ordenadas para manter retorno determinístico;
- IDs e refs podem aparecer nos erros;
- config e material sensível nunca aparecem;
- violations estruturais finais de RunSnapshot retornam Ecto.Changeset;
- erros operacionais de banco continuam como exceções;
- tradução HTTP permanece fora deste slice.

## Repetição e idempotency

Duas chamadas bem-sucedidas para o mesmo EnvironmentDeployment criam duas Runs e dois RunSnapshots distintos.

Não existem neste slice:

- idempotency key;
- invocation record;
- deduplicação;
- vínculo de provenance em Run;
- EnvironmentDeployment ID no formato RunSnapshot v1.

Chamadas concorrentes podem criar Runs distintas a partir do mesmo estado coerente. Uma repetição após timeout ambíguo pode duplicar a Run. Idempotência futura deverá ser explícita e não inferida pelo deployment ID.

Uma falha confirmada causa rollback e não deixa Run ou snapshot parcial.

## Ratificação

Todas as decisões necessárias para materializar este slice foram ratificadas. A implementação deve seguir a specification relacionada e não ampliar o escopo sem novo registro decisório.

## Alternativas consideradas para a topologia

### Definition JSONB dentro de PackageVersion

Rejeitada para este slice porque criaria um segundo document contract antes da ratificação do Package Manifest e reduziria a capacidade do banco de proteger referências e cardinalidade.

### Usar diretamente o Package Manifest como persistência

Rejeitada neste slice porque os field names de `package-manifest-v1.md` ainda não estavam ratificados. O ADR-0023 os ratificou posteriormente sem substituir a projeção relacional.

### Duplicar ConnectorVersion no endpoint

Rejeitada porque `Operation` já pertence a uma ConnectorVersion. A duplicação criaria duas referências que poderiam divergir.

## Estado atual

Materializado:

- `Run` e `RunSnapshot`;
- `RunSnapshot.DefinitionV1`;
- criação atômica por `Executions.Runs.create/1`;
- eligibility e recovery de Runs `pending` com formato suportado;
- `Connector`, `ConnectorVersion` e `Operation` no Catalog;
- publicação transacional e sealing de ConnectorVersion com suas Operations;
- imutabilidade de conteúdo e validação UTF-8 dessas authorities;
- `Contract` e `ContractVersion` identity-only no Catalog;
- publicação imediata e imutabilidade de ContractVersion;
- `Package`, `PackageVersion` e `PackageVersionEndpoint` no Catalog;
- publicação atômica, cardinalidade 1 Source → 1..N Destinations, ordem e role compatibility protegidas no PostgreSQL;
- leitura pública da projeção imutável por PackageVersion;
- `Connection`, `Secret` e `SecretVersion` no context Connections;
- APIs públicas de create/get/update/disable de Connection e criação de Secret/SecretVersion;
- API pública `Connections.lock_active/3` para leitura bloqueada em ordem determinística;
- API pública `Connections.Secrets.fetch_versions/3` para identities exatas e scope-compatible;
- scope explícito de Organization/Environment com FKs compostas;
- validação de parents ativos sob locks compartilhados na ordem Organization → Environment;
- config não sensível validada como JSON object;
- binding opcional e exato protegido contra SecretVersion cross-scope;
- unicidade e imutabilidade de SecretVersion no PostgreSQL;
- ausência de raw secret, ciphertext, provider locator e credential na persistência;
- identidade `Integration` organization-scoped ligada a uma Package estável;
- APIs públicas `Integrations.create/1`, `get/1` e `disable/1`;
- API pública `Integrations.lock_active/2` para workflows compostos;
- validação de Organization ativa sob lock compartilhado e disable idempotente;
- imutabilidade de Organization, Package e identidade da Integration no PostgreSQL;
- `EnvironmentDeployment` e `EnvironmentDeploymentBinding` com scope explícito;
- APIs públicas `Integrations.Deployments.create/1`, `get/1` e `replace/2`;
- API pública `Integrations.Deployments.fetch_resolution_scope/1` para descobrir somente os parent IDs imutáveis sem ler bindings;
- API pública `Integrations.Deployments.lock_for_resolution/1` para proteger deployment e bindings;
- um deployment completo por Integration/Environment com PackageVersion, configs separadas e bindings completos;
- validação transacional de authorities ativas, PackageVersion, refs e compatibilidade de Connector;
- locks ordenados de Organization, Environment, Integration, deployment e Connections;
- constraints e triggers protegendo identidade, JSON objects, cobertura, PackageVersion e Connector compatibility.
- `LeafcutterRuntime.Runs.create_from_deployment/1` como uma única transação de descoberta, locks, revalidação, resolução e criação de Run;
- deep merge recursivo com precedência de local config, substituição de arrays e `null` como override;
- congelamento de PackageVersion, ContractVersions, ordem de destinations, Connection configs e SecretVersion IDs na definition v1;
- rollback integral para erros semânticos e criação distinta em chamadas repetidas.

## Futuro preservado

Continuam fora deste slice:

- JSON Schema completo do Package Manifest;
- build e instalação física de packages;
- Connector/Operation/Transport executáveis;
- raw secrets, secret provider, OAuth e rotação;
- promotion, homologation e histórico;
- actor, invocation e idempotency key;
- carregamento do snapshot no RunCoordinator;
- Record, Delivery, Attempt, Checkpoint e Broadway.

## Evolução posterior

Os ADRs 0019, 0021 e 0022 materializaram ContractVersion, Operation e Transport HTTP sem
alterar a projeção deste ADR. O ADR-0023 ratificou posteriormente os field names mínimos do
Manifest v1, seu digest em PackageVersion, a inventory explícita de build e a resolução
compilada; 26C2 ainda não está materializado. Auto-publication do Catalog a partir de package
code continua proibida.

## Consequências

- Catalog já publica ConnectorVersion e Operations sem transformar o manifest aberto em contract persistido;
- o resolver obtém refs, Operations e ContractVersions por uma API pública do owner;
- referências relacionais e cardinalidade são revalidadas antes da criação da Run;
- a ingestão futura de packages precisará traduzir o manifest para a projeção interna;
- a próxima fronteira volta a ser Contracts/JSV e os contracts executáveis de Connector/Operation/Transport.

## Evidência

- `docs/decisions/ADR-0017-run-snapshot-v1.md`;
- `docs/specifications/run-snapshot-v1.md`;
- `docs/architecture/contextos-e-ownership.md`;
- `docs/architecture/modelo-conceitual.md`;
- `docs/architecture/integration-packages.md`;
- `docs/specifications/package-manifest-v1.md`;
- `apps/leafcutter_core/lib/leafcutter/integrations/deployments.ex`;
- `apps/leafcutter_core/priv/repo/migrations/20260828090000_create_environment_deployments.exs`;
- `apps/leafcutter_core/test/leafcutter/integrations/deployments_test.exs`;
- `apps/leafcutter_runtime/lib/leafcutter_runtime/runs.ex`;
- `apps/leafcutter_runtime/test/leafcutter_runtime/runs_resolution_test.exs`;
- `docs/checkpoint/CURRENT.md`.

## Evolução posterior

O ADR-0019 dividiu a fronteira executável citada neste ADR. ContractVersion + JSON Schema/JSV forma o Slice 26A já ratificado; Operation executável e HTTP foram preservados separadamente como 26B/26C. Essa evolução não altera o modelo upstream, o lock order nem RunSnapshot v1 materializados aqui.
