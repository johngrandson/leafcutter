# ADR-0017 — RunSnapshot v1 como definição executável imutável

- Status: Accepted
- Estado de implementação: NÃO MATERIALIZADO

## Contexto

`Run` materializa hoje lifecycle e ownership, mas não contém a definição necessária para executar uma integração. Por isso, uma Run `pending` ainda não pode entrar com segurança no recovery automático.

Catalog, Connections e Integrations continuam ratificados para slices posteriores. A fundação de RunSnapshot deve permitir criar uma definição executável validada sem antecipar schemas ou ownership desses contexts.

## Decisão

`RunSnapshot` pertence ao context `Executions` e mantém uma relação 1:1 dependente de `Run`.

Persistência ratificada:

```text
run_snapshots
├── run_id          UUID, primary key e foreign key para runs.id
├── format_version  positive integer
└── definition      JSONB object
```

Regras físicas:

- `run_id` é a identidade do snapshot; não existe id independente;
- o snapshot não possui timestamps próprios;
- a foreign key usa `ON DELETE CASCADE`;
- `format_version > 0`;
- `definition` é obrigatório e deve ser um JSON object;
- um trigger no PostgreSQL rejeita `UPDATE` em `run_snapshots`;
- não existe trigger de `DELETE`: a remoção acontece somente como consequência da futura retenção de `Run`.

`definition` não é um map arbitrário. A aplicação valida uma estrutura tipada e a serializa para JSONB. O formato v1 congela:

- a `PackageVersion` executável;
- uma source com `ref`, `ContractVersion` e Connection resolvida;
- uma ou mais destinations com `ref`, `ContractVersion` e Connection resolvida;
- config não sensível efetiva;
- a referência exata à `SecretVersion`, quando existir.

Raw secrets nunca entram no snapshot.

`PackageVersion` permanece authority para ConnectorVersion, Operation, Transformation, Enrichment, Interceptor e SourceIdentity. O snapshot não duplica essa topologia.

## Criação e leitura públicas

A API pública ratificada é:

```elixir
Leafcutter.Executions.Runs.create(definition_attrs)
```

Contrato:

```elixir
{:ok, Run.t()} | {:error, Ecto.Changeset.t()}
```

A estrutura é validada antes da transação. Um `Ecto.Multi` insere `Run` com status `pending` e o respectivo `RunSnapshot` na mesma transação. O caller não define `id`, `status`, ownership, `generation` ou `ownership_acquired_at`.

Não existe criação pública de Run sem snapshot, attach posterior, draft, update, replace, upsert ou CRUD independente de RunSnapshot.

Leitura explícita:

```elixir
Leafcutter.Executions.Runs.fetch_snapshot(run_id)
```

Retornos:

```elixir
{:ok, RunSnapshot.t()}
{:error, :run_not_found | :run_snapshot_not_found}
```

Duas chamadas válidas de `create/1` criam duas Runs. Idempotency e deduplication não pertencem a este slice.

## Eligibility e recovery

Uma Run `pending` é elegível para claim e recovery somente quando possui snapshot em formato suportado.

No primeiro formato:

```elixir
RunSnapshot.current_format_version() == 1
RunSnapshot.supported_format_versions() == [1]
```

`Runs.claim/2` passa a distinguir:

- `pending` com snapshot v1: claim normal;
- `pending` sem snapshot: `:run_snapshot_not_found`;
- `pending` com formato não suportado: `:unsupported_run_snapshot_format`;
- `running`: comportamento atual de ownership e fencing;
- estado terminal: `:run_not_claimable`.

`Runs.claim_recoverable/3` considera:

- Runs `running` sem owner ou com owner expirado, preservando o recovery atual;
- Runs `pending`, sem owner, com snapshot em formato suportado.

O claim muda `pending` para `running`, persiste owner e nova generation e somente depois do commit inicia a árvore local.

Runs legadas `running` sem snapshot continuam recuperáveis. Runs legadas `pending` sem snapshot permanecem inelegíveis.

## Versionamento e imutabilidade

- formatos novos valem somente para novas Runs;
- snapshot existente não é migrado nem reinterpretado in-place;
- o decoder é selecionado por `format_version`;
- Runs existentes podem continuar sem snapshot;
- novas Runs criadas pela API pública sempre possuem snapshot.

## Validação neste slice

A validação inicial é estrutural. A existência semântica de PackageVersion, ContractVersion, Connection e SecretVersion será validada quando os contexts owners forem materializados.

## Consequências

- uma Run nova nasce com definição executável completa para o formato conhecido;
- o PostgreSQL protege atomicidade e imutabilidade;
- o formato versionado evita depender do estado mutável das integrações;
- recovery de `pending` deixa de inferir completude a partir da linha mínima de `Run`;
- Catalog, Connections e Integrations não são antecipados;
- Broadway, Record, Delivery e data plane continuam fora deste slice;
- a futura criação a partir de `EnvironmentDeployment` resolverá as authorities upstream e chamará a API pública de Executions.

## Fora do escopo

O formato v1 não inclui organization, environment, integration ou deployment ids, revision, actor, invocation, input por Run, idempotency key, artifact digest, retry, batch ou concurrency policy.

Lifecycle completo, terminalização, retenção, autenticação, secrets concretos e carregamento da definição no coordinator continuam decisões ou slices posteriores.

## Alternativas rejeitadas

- armazenar o snapshot como colunas em `runs`;
- dar identidade e lifecycle independentes ao snapshot;
- normalizar o formato v1 em tabelas filhas antes de existir necessidade de query relacional;
- permitir atualização do snapshot;
- criar primeiro Catalog, Connections e Integrations para então definir a fundação;
- tornar Runs `pending` elegíveis sem prova persistida de definição suportada.
