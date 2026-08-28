# RunSnapshot v1

- Status decisório: Accepted
- Estado de implementação: MATERIALIZADO
- ADR: `docs/decisions/ADR-0017-run-snapshot-v1.md`

## Objetivo

Definir o contrato persistido, imutável e versionado que acompanha uma `Run` desde sua criação pública.

Neste slice, o control plane usa a presença e a versão suportada do snapshot como prova de eligibility de uma Run `pending`. Isso não comprova ainda que as referências existem nem que a Run é semanticamente executável. A resolução a partir de `EnvironmentDeployment`, o carregamento no coordinator e a execução no data plane pertencem a slices posteriores.

## Ownership e boundary

`RunSnapshot` pertence a `Leafcutter.Executions`.

`Leafcutter.Executions.Runs.create/1` recebe uma definition já resolvida. O futuro workflow de `EnvironmentDeployment → definition v1` pertence à orchestration em `leafcutter_runtime`; Executions não consulta internals de Catalog, Connections ou Integrations.

O snapshot referencia identifiers owned por contexts futuros sem assumir seus schemas físicos. `PackageVersion` continua authority da topologia executável; o snapshot não cria authorities paralelas.

## Persistência

Tabela:

```text
run_snapshots
├── run_id          uuid, primary key, not null
├── format_version  integer, not null
└── definition      jsonb, not null
```

Constraints:

```text
PRIMARY KEY (run_id)
FOREIGN KEY (run_id) REFERENCES runs(id) ON DELETE CASCADE
CHECK (format_version > 0)
CHECK (jsonb_typeof(definition) = 'object')
```

A tabela não possui `id` independente nem timestamps.

Cardinalidade:

- uma Run legada possui zero ou um snapshot;
- toda Run criada por `Runs.create/1` possui exatamente um snapshot;
- um snapshot pertence a exatamente uma Run.

Um trigger no PostgreSQL rejeita todo `UPDATE` de `run_snapshots`. Não existe API pública de update, replace, upsert, attach ou delete.

A regra da aplicação é remover o snapshot somente quando uma futura política de retenção remover a Run, usando `ON DELETE CASCADE`. Não existe trigger contra `DELETE`; portanto, privileged SQL pode remover e reinserir diretamente uma linha. O banco garante unicidade, vínculo, cascade e rejeição de update, não inviolabilidade absoluta contra administração direta.

## Versionamento

Contrato inicial:

```elixir
RunSnapshot.current_format_version() == 1
RunSnapshot.supported_format_versions() == [1]
```

Regras:

- `format_version` seleciona o decoder;
- versões novas se aplicam somente a novas Runs;
- snapshots persistidos não são migrados, reescritos ou reinterpretados in-place;
- formato persistido não suportado torna uma Run `pending` inelegível;
- um documento v1 já válido não pode se tornar inválido por endurecimento do decoder v1;
- mudança incompatível de shape ou validação exige nova versão;
- rolling upgrade e remoção futura de formatos suportados continuam abertos.

## Definition v1

Representação JSON canônica:

```json
{
  "package_version_id": "uuid",
  "source": {
    "ref": "source",
    "contract_version_id": "uuid",
    "connection": {
      "id": "uuid",
      "config": {},
      "secret_version_id": "uuid-or-null"
    }
  },
  "destinations": [
    {
      "ref": "crm",
      "contract_version_id": "uuid",
      "connection": {
        "id": "uuid",
        "config": {},
        "secret_version_id": "uuid-or-null"
      }
    }
  ],
  "effective_config": {}
}
```

A forma persistida usa exatamente as chaves JSON mostradas. Campos semânticos desconhecidos são rejeitados. Normalização de atom/string keys no input é detalhe de implementação e não altera o JSON persistido.

### Campos

| Campo | Tipo | Regra |
|---|---|---|
| `package_version_id` | UUID | obrigatório |
| `source` | object | exatamente uma source |
| `source.ref` | non-empty string | único no snapshot |
| `source.contract_version_id` | UUID | obrigatório |
| `source.connection.id` | UUID | obrigatório |
| `source.connection.config` | JSON object | config resolvida; deve ser não sensível |
| `source.connection.secret_version_id` | UUID ou null | referência exata; nunca raw secret |
| `destinations` | array | pelo menos um item |
| `destinations[].ref` | non-empty string | único no snapshot |
| `destinations[].contract_version_id` | UUID | obrigatório |
| `destinations[].connection.id` | UUID | obrigatório |
| `destinations[].connection.config` | JSON object | config resolvida; deve ser não sensível |
| `destinations[].connection.secret_version_id` | UUID ou null | referência exata; nunca raw secret |
| `effective_config` | JSON object | config efetiva; deve ser não sensível |

Todos os `ref` de source e destinations são não vazios e mutuamente únicos dentro do snapshot.

A ordem do array `destinations` é preservada como dado, mas não define prioridade, scheduling ou ordem de execução.

`definition` é validated typed data serializada como JSONB. Aceitar um JSON object no banco não substitui a validação estrutural da aplicação.

### Authority preservada

`PackageVersion` permanece authority para:

```text
ConnectorVersion
Operation
Transformation
Enrichment
Interceptor
SourceIdentity
```

Esses elementos não são copiados para o formato v1.

As referências de PackageVersion, ContractVersion, Connection e SecretVersion são uma resolução congelada. Sua consistência com as authorities upstream será verificada pelo futuro resolver; o primeiro slice não consegue comprová-la semanticamente.

`source.ref` e `destinations[].ref` são nomes do formato RunSnapshot v1. Eles não ratificam field names do Package Manifest, que continua DRAFT.

### Raw secrets e config

Raw secrets nunca devem ser armazenados em `definition`.

A validação estrutural consegue verificar que `config` e `effective_config` são objects, mas não consegue provar que seus valores não contêm material sensível. Até existir o resolver de EnvironmentDeployment, essa regra é responsabilidade do caller confiável de `Runs.create/1`. O resolver futuro deve separar config não sensível de `SecretVersion` antes da chamada.

A opção `secret_version_id: UUID | null` define apenas o binding do snapshot v1; não fecha o modelo completo de Connections, rotação, revogação ou retenção de SecretVersion.

### Dados excluídos

O formato v1 não contém:

```text
organization_id
environment_id
integration_id
environment_deployment_id
deployment revision
actor
invocation
per-Run input
idempotency key
artifact digest
retry policy
batch policy
concurrency policy
raw secrets
```

## Validação

A validação deste slice é estrutural:

- campos obrigatórios e ausência de campos desconhecidos;
- UUIDs válidos;
- objects e arrays nos tipos esperados;
- exatamente uma source;
- pelo menos uma destination;
- `ref` não vazio e único;
- `config` e `effective_config` como JSON objects;
- `secret_version_id` como UUID ou null.

Ficam para os contexts owners e para o resolver futuro:

- existência das referências;
- compatibilidade PackageVersion/ContractVersion;
- validade dos bindings de Connection;
- lifecycle de SecretVersion;
- merge e provenance de config;
- enforcement semântico de ausência de raw secrets.

## Criação pública

API:

```elixir
Leafcutter.Executions.Runs.create(definition_attrs)
```

`definition_attrs` é o próprio objeto lógico da definition v1. Não é um envelope com `definition` ou `format_version`.

Contrato:

```elixir
@spec create(map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
```

O caller não pode definir:

```text
Run.id
Run.status
Run.owner_node_id
Run.generation
Run.ownership_acquired_at
RunSnapshot.format_version
```

O workflow:

```text
validate definition_attrs
→ Ecto.Multi
  → insert Run(status: pending)
  → insert RunSnapshot(
      run_id: Run.id,
      format_version: current format,
      definition: validated definition
    )
→ commit
→ return Run
```

Qualquer falha faz rollback integral. O retorno de sucesso contém apenas `Run`.

Não existe criação pública de Run sem snapshot. Duas chamadas válidas criam duas Runs; idempotency e deduplication não são inferidas.

Runs legadas já persistidas podem continuar sem snapshot.

## Leitura pública

API:

```elixir
Leafcutter.Executions.Runs.fetch_snapshot(run_id)
```

Contrato:

```elixir
@spec fetch_snapshot(Run.id()) ::
        {:ok, RunSnapshot.t()}
        | {:error, :run_not_found | :run_snapshot_not_found}
```

`:run_not_found` tem precedência quando a Run não existe. `:run_snapshot_not_found` identifica uma Run existente sem snapshot.

## Claim explícito

`Runs.claim/2` preserva ownership e fencing atuais e adiciona as seguintes classificações:

| Estado da Run | Snapshot | Resultado |
|---|---|---|
| `pending` | formato suportado | claim; muda para `running` |
| `pending` | ausente | `{:error, :run_snapshot_not_found}` |
| `pending` | formato não suportado | `{:error, :unsupported_run_snapshot_format}` |
| `running` | qualquer, inclusive ausente ou não suportado | comportamento atual |
| terminal | qualquer | `{:error, :run_not_claimable}` |

O type `Runs.claim_error/0` passa a incluir:

```elixir
:run_snapshot_not_found
| :unsupported_run_snapshot_format
```

A validação do runtime node e as regras atuais de active owner, stale owner e generation permanecem válidas.

Compatibilidade:

- uma Run legada `pending` sem snapshot deixa de ser claimable;
- uma Run legada `running` continua claimable/recoverable;
- uma Run `running` com formato desconhecido continua seguindo ownership e fencing atuais.

## Recovery automático

`Runs.claim_recoverable/3` seleciona, no mesmo batch:

- Runs `running` sem owner;
- Runs `running` com owner expirado;
- Runs `pending`, sem owner, com snapshot em formato suportado.

Runs `pending` sem snapshot ou com formato não suportado não são selecionadas.

Após o lock e o claim:

```text
pending → running
owner_node_id → claimant
generation → generation + 1
ownership_acquired_at → PostgreSQL clock
commit
→ local RunSupervisor startup
```

Continuam inalterados:

- relógio e liveness no PostgreSQL;
- `FOR UPDATE SKIP LOCKED`;
- batch size e ordering atuais;
- exclusions e backoff por Run;
- fencing;
- reconstrução das árvores já owned;
- início da árvore local somente depois do commit.

O RunCoordinator ainda não carrega nem executa a definition. Eligibility neste slice é uma regra do control plane.

## Critérios de aceitação do slice

- a migration cria constraints, cascade e trigger contra update;
- uma definition v1 válida cria Run e RunSnapshot atomicamente;
- definition inválida não persiste nenhuma das duas linhas;
- campos desconhecidos são rejeitados;
- o caller não controla campos internos da Run ou a versão do snapshot;
- duas criações válidas produzem Runs distintas;
- `fetch_snapshot/1` distingue Run ausente de snapshot ausente;
- `UPDATE` direto no snapshot é rejeitado pelo PostgreSQL;
- delete da Run remove o snapshot por cascade;
- a aplicação não expõe delete direto de snapshot;
- claim de `pending` exige snapshot em formato suportado;
- recovery inclui `pending` elegível;
- recovery preserva Runs legadas `running` sem snapshot;
- formato desconhecido nunca inicia uma Run `pending`;
- testes existentes de ownership, fencing e recovery continuam passando.

## Fora deste slice

Não adicionar:

- `create_from_deployment/1`;
- resolver de `EnvironmentDeployment`;
- schemas de Catalog, Connections ou Integrations;
- actor, invocation ou idempotency;
- PubSub wake-up, Oban job ou nova queue;
- carregamento do snapshot no `RunCoordinator`;
- Broadway, Record, Delivery ou qualquer data plane;
- política concreta de retenção;
- política de rolling upgrade de formatos.
