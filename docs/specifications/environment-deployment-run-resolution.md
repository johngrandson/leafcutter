# EnvironmentDeployment → RunSnapshot v1

- Status decisório: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO — AUTHORITIES UPSTREAM COMPLETAS; RESOLVER PENDENTE
- ADR: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`

## Objetivo

Definir o menor conjunto de authorities upstream e o workflow transacional capaz de criar uma Run a partir de um EnvironmentDeployment persistido, congelando uma definition v1 semanticamente resolvida no RunSnapshot.

O contract de destino permanece `docs/specifications/run-snapshot-v1.md`.

## Ownership e applications

```text
leafcutter_core
├── Catalog
├── Connections
└── Integrations

leafcutter_runtime
├── Executions
└── orchestration de create_from_deployment/1
```

Regras:

- cada context preserva seus schemas, queries e invariantes;
- composição usa somente APIs públicas;
- referências por ID não autorizam acesso a internals;
- `Executions.Runs.create/1` continua recebendo uma definition v1 já resolvida;
- nenhuma nova OTP application, service layer, GenServer ou workflow abstraction é criada.

## Catalog mínimo

### Entidades

```text
Connector
└── ConnectorVersion
    └── Operation

Contract
└── ContractVersion

Package
└── PackageVersion
    └── PackageVersionEndpoint
```

`Connector`, `Contract` e `Package` são identidades globais estáveis e sem tenancy.

Campos lógicos versionados:

```text
ConnectorVersion
├── id
├── connector_id
├── version
└── published_at

Operation
├── id
├── connector_version_id
├── ref
└── role: source | destination

ContractVersion
├── id
├── contract_id
├── version
└── published_at

PackageVersion
├── id
├── package_id
├── version
└── published_at

PackageVersionEndpoint
├── id
├── package_version_id
├── ref
├── role: source | destination
├── position
├── operation_id
└── contract_version_id
```

### Invariantes

- `version` é uma string opaca e única dentro da identidade pai;
- Semantic Versioning não é interpretado;
- versões nascem publicadas e não possuem draft;
- conteúdo versionado não aceita update ou delete;
- ConnectorVersion é publicada atomicamente com suas Operations;
- Operation pertence a exatamente uma ConnectorVersion;
- `Operation.ref` é único dentro da ConnectorVersion;
- PackageVersion é publicada atomicamente com seus endpoints;
- cada PackageVersion possui exatamente uma source e uma ou mais destinations;
- refs de endpoints são não vazios e mutuamente únicos;
- source usa uma Operation source e destination usa uma Operation destination;
- destination `position` é única dentro da PackageVersion;
- a ordem é dado persistido, não prioridade de execução;
- ContractVersion materializa somente identidade neste slice;
- JSON Schema e JSV permanecem posteriores;
- a projeção relacional não define field names do Package Manifest.

### APIs públicas

```text
Leafcutter.Catalog.Connectors
Leafcutter.Catalog.Contracts
Leafcutter.Catalog.Packages
```

As APIs de publicação recebem a versão e seus filhos como uma unidade lógica e persistem tudo atomicamente.

## Connections mínimo

### Entidades

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

### Invariantes

- Connection, Secret e SecretVersion são environment-scoped;
- Organization e Environment são persistidos explicitamente;
- o banco rejeita combinações incompatíveis de Organization e Environment;
- Connection referencia Connector, nunca ConnectorVersion;
- `config` é um JSON object não sensível;
- `secret_version_id` é opcional e selecionado explicitamente;
- não existe seleção automática da última versão;
- SecretVersion é imutável;
- `version` é única dentro de Secret;
- a SecretVersion vinculada precisa pertencer ao mesmo Organization e Environment da Connection;
- updates de Connection podem substituir config ou SecretVersion;
- disable é idempotente;
- Connection desabilitada não participa de nova resolução;
- raw secret, ciphertext, provider locator e credential não são aceitos nem persistidos.

### APIs públicas

```text
Leafcutter.Connections.create/1
Leafcutter.Connections.get/1
Leafcutter.Connections.update/2
Leafcutter.Connections.disable/1
Leafcutter.Connections.lock_active/3

Leafcutter.Connections.Secrets.create/1
Leafcutter.Connections.Secrets.create_version/1
Leafcutter.Connections.Secrets.fetch_versions/3
```

### Estado materializado

O modelo mínimo está materializado em `leafcutter_core`:

- Connection referencia Connector estável e aceita somente config JSON object não sensível;
- Secret e Connection persistem Organization/Environment explícitos e compatíveis;
- SecretVersion contém somente identidade/version, é única dentro de Secret e imutável;
- binding de Connection é opcional, exato e protegido contra cross-scope;
- writes seguram locks compartilhados de Organization e Environment antes de Connection;
- `lock_active/3` bloqueia Connections únicas em ordem de ID para workflows compostos;
- `Secrets.fetch_versions/3` valida identities exatas e scope em batch, sem latest-version selection;
- update substitui somente config e/ou SecretVersion; disable preserva um timestamp idempotente;
- raw secret, ciphertext, provider locator, credential, OAuth, rotation e revocation não foram materializados.

## Integrations mínimo

### Entidades

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
├── id
├── environment_deployment_id
├── ref
└── connection_id
```

### Invariantes

- Integration é organization-scoped;
- Integration referencia uma identidade estável de Package;
- o Package da Integration não é alterado;
- existe no máximo um EnvironmentDeployment por Integration e Environment;
- o deployment não possui revision ou lifecycle independente neste slice;
- create persiste um estado completo;
- replace troca PackageVersion, configs e bindings atomicamente;
- promotable config e local config são JSON objects não sensíveis;
- cada binding armazena somente endpoint ref e Connection;
- refs de bindings são únicas dentro do deployment;
- role, posição, Operation e ContractVersion vêm da PackageVersion;
- SecretVersion vem do binding atual da Connection;
- Integration desabilitada bloqueia todas as suas resoluções.

### Validação em create e replace

No instante da escrita:

- Organization e Environment existem, correspondem e estão ativos;
- Integration existe, pertence à Organization e está ativa;
- PackageVersion pertence ao Package da Integration;
- bindings correspondem exatamente aos endpoints da PackageVersion;
- Connections pertencem ao mesmo Organization e Environment;
- Connections estão ativas;
- Connector de cada Connection é compatível com a ConnectorVersion da Operation.

Essas validações são repetidas na criação da Run porque deployment e Connections são mutáveis.

### APIs públicas

```text
Leafcutter.Integrations.create/1
Leafcutter.Integrations.get/1
Leafcutter.Integrations.disable/1
Leafcutter.Integrations.lock_active/2

Leafcutter.Integrations.Deployments.create/1
Leafcutter.Integrations.Deployments.get/1
Leafcutter.Integrations.Deployments.replace/2
Leafcutter.Integrations.Deployments.lock_for_resolution/1
```

### Estado materializado

O modelo mínimo está materializado em `leafcutter_core`:

- Integration é organization-scoped, referencia Package estável e possui lifecycle mínimo;
- EnvironmentDeployment possui identidade imutável e é único por Integration/Environment;
- create e replace persistem PackageVersion, configs separadas e todos os bindings atomicamente;
- bindings cobrem exatamente os endpoints e guardam somente ref + Connection ID;
- writes revalidam Organization, Environment, Integration, Connections e compatibilidade de PackageVersion/Connector sob locks determinísticos;
- constraints e triggers protegem JSON objects, identidade, PackageVersion, cobertura e Connector compatibility;
- `get/1` devolve bindings ordenados por ref;
- `lock_for_resolution/1` mantém deployment e bindings sob shared locks até o fim da transação;
- effective config e congelamento de SecretVersion continuam responsabilidades do resolver.

## Effective config

```text
promotable_config
        ↓
recursive merge
        ↑
local_config wins
        ↓
effective_config
```

Algoritmo:

1. quando os dois valores são objects, combinar suas chaves recursivamente;
2. em qualquer outro conflito, usar o valor local;
3. substituir arrays integralmente;
4. tratar `null` como valor de override;
5. preservar chaves presentes somente em um lado.

Connection config não participa do merge. Package defaults e secrets também não participam.

O deployment preserva promotable e local config. O RunSnapshot persiste somente effective config.

## Resolver transacional

API:

```elixir
LeafcutterRuntime.Runs.create_from_deployment(environment_deployment_id)
```

Fluxo:

```text
one shared Repo transaction
→ lock mutable authorities through public APIs
→ fetch immutable Catalog and SecretVersion projections
→ validate semantic consistency
→ merge effective config
→ build definition v1
→ Executions.Runs.create/1
→ commit Run + RunSnapshot
```

Ordem obrigatória:

```text
1. Organization
2. Environment
3. Integration
4. EnvironmentDeployment
5. Connections ordered by ID
6. PackageVersion projection
7. SecretVersion identities
```

Organization, Environment, Integration, deployment e Connections recebem locks de leitura que bloqueiam alterações concorrentes. Authorities imutáveis não precisam de lock.

O deployment é bloqueado antes da leitura de bindings. Connections são bloqueadas em ordem de ID. Nenhum efeito externo ocorre dentro da transação.

## Mapeamento para definition v1

```text
definition.package_version_id
← EnvironmentDeployment.package_version_id

definition.source.ref
← source PackageVersionEndpoint.ref

definition.source.contract_version_id
← source PackageVersionEndpoint.contract_version_id

definition.source.connection
← locked source Connection

definition.destinations
← destination endpoints ordered by position
   + corresponding locked Connections

definition.effective_config
← deep_merge(promotable_config, local_config)
```

Cada connection no snapshot contém exatamente:

```text
id
config
secret_version_id
```

O resolver não adiciona Organization, Environment, Integration ou Deployment IDs ao formato v1.

## Retorno e erros

```elixir
@spec create_from_deployment(EnvironmentDeployment.id()) ::
        {:ok, Run.t()}
        | {:error, create_from_deployment_error()}

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

Refs em erros são ordenadas. Erros podem expor IDs e refs, nunca config ou material sensível. Erros operacionais de banco continuam como exceções.

## Repetição

Duas chamadas bem-sucedidas para o mesmo deployment criam duas Runs distintas.

Chamadas concorrentes também podem criar Runs distintas. Não existem idempotency key, invocation record ou deduplicação. Timeout ambíguo pode resultar em duplicação.

Falha confirmada causa rollback integral.

## Critérios de aceitação

- versions e filhos do Catalog são publicados atomicamente e são imutáveis;
- cardinalidade 1 source → 1..N destinations é validada;
- Connection e SecretVersion preservam scope de Organization/Environment;
- nenhum raw secret é aceito ou persistido;
- deployment create/replace persiste estado completo e semanticamente válido naquele instante;
- replace não deixa bindings parciais;
- deep merge segue a precedência ratificada;
- resolver usa somente APIs públicas dos contexts;
- resolução e RunSnapshot pertencem à mesma transação;
- alteração concorrente de deployment ou Connection não produz snapshot híbrido;
- definition v1 contém refs e configs resolvidas corretas;
- destination order segue PackageVersionEndpoint.position;
- erro semântico não persiste Run;
- duas chamadas válidas criam Runs distintas;
- Run resultante permanece pending e elegível para RunRecovery;
- `mix quality` passa.

## Fora do escopo

- Package Manifest JSON Schema;
- conteúdo JSON Schema de ContractVersion e validação JSV;
- package build/release;
- Connector/Operation/Transport executáveis;
- raw secret storage ou retrieval;
- OAuth, rotation, revocation e retention;
- deployment revision, history, promotion e rollback;
- event, schedule, webhook ou ingestion triggers;
- actor, invocation e idempotency key;
- vínculo de provenance na Run;
- carregamento do snapshot no RunCoordinator;
- Record, Delivery, Attempt, Checkpoint e Broadway;
- HTTP/API translation.
