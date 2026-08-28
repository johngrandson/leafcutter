# ADR-0017 — RunSnapshot v1 como definição executável imutável

- Status: Accepted
- Estado de implementação: MATERIALIZADO

## Contexto

Antes deste slice, `Run` materializava lifecycle e ownership, mas não continha a definição necessária para executar uma integração. Por isso, uma Run `pending` não podia entrar no recovery automático.

Catalog, Connections e Integrations continuam ratificados para slices posteriores. A fundação de RunSnapshot deve criar um contrato persistido e versionado sem antecipar schemas ou ownership desses contexts.

## Decisão

`RunSnapshot` pertence ao context `Executions` e depende de `Run`.

Persistência ratificada:

```text
run_snapshots
├── run_id          UUID, primary key e foreign key para runs.id
├── format_version  positive integer
└── definition      JSONB object
```

Cardinalidade:

- uma Run legada pode possuir zero ou um snapshot;
- toda nova Run criada pela API pública possui exatamente um snapshot;
- um snapshot pertence a exatamente uma Run.

Regras físicas:

- `run_id` é a identidade do snapshot; não existe id independente;
- o snapshot não possui timestamps próprios;
- a foreign key usa `ON DELETE CASCADE`;
- `format_version > 0`;
- `definition` é obrigatório e deve ser um JSON object;
- um trigger no PostgreSQL rejeita `UPDATE` em `run_snapshots`.

Não existe API pública de `DELETE`. A regra de lifecycle é remover o snapshot somente como consequência da futura retenção de `Run`, usando o cascade. Como não existe trigger de `DELETE`, privileged SQL continua capaz de remover e reinserir uma linha; esta decisão não afirma uma garantia absoluta contra administração direta do banco.

`definition` não é um map arbitrário. A aplicação valida uma estrutura tipada e a serializa para JSONB. O formato v1 congela:

- a referência à `PackageVersion`;
- uma source com `ref`, `ContractVersion` e Connection resolvida;
- uma ou mais destinations com `ref`, `ContractVersion` e Connection resolvida;
- config não sensível efetiva;
- a referência exata à `SecretVersion`, quando existir.

`PackageVersion` permanece authority para ConnectorVersion, Operation, Transformation, Enrichment, Interceptor e SourceIdentity. O snapshot não duplica essa topologia. As referências copiadas são uma resolução congelada que o futuro resolver deve validar contra as authorities upstream.

`source.ref` e `destinations[].ref` são identifiers locais do formato do snapshot. Esta decisão não ratifica nomes de campos do Package Manifest, que continua DRAFT. A ordem do array de destinations não define prioridade de execução.

Raw secrets nunca devem entrar no snapshot. No primeiro slice, essa é uma responsabilidade do caller confiável; validação estrutural de JSON não consegue provar que um valor arbitrário de config não contém material sensível. O futuro resolver de EnvironmentDeployment deve aplicar essa regra antes de chamar Executions.

## Criação e leitura públicas

A API pública ratificada é:

```elixir
Leafcutter.Executions.Runs.create(definition_attrs)
```

`definition_attrs` representa o próprio objeto lógico da definition v1. `format_version` é escolhido internamente e não é aceito do caller. A forma JSON persistida usa exatamente os campos definidos na specification; campos semânticos desconhecidos são rejeitados. Normalização de chaves de input é detalhe de implementação e não altera o formato persistido.

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

Uma Run `pending` é elegível para claim e recovery no control plane somente quando possui snapshot em formato suportado. Essa regra não comprova ainda que as referências existem nem que o data plane consegue executar a definição.

No primeiro formato:

```elixir
RunSnapshot.current_format_version() == 1
RunSnapshot.supported_format_versions() == [1]
```

`Runs.claim/2` passa a distinguir:

- `pending` com snapshot v1: claim normal;
- `pending` sem snapshot: `:run_snapshot_not_found`;
- `pending` com formato não suportado: `:unsupported_run_snapshot_format`;
- `running`: comportamento atual de ownership e fencing, independentemente de snapshot;
- estado terminal: `:run_not_claimable`.

`Runs.claim_recoverable/3` considera:

- Runs `running` sem owner ou com owner expirado, preservando o recovery atual;
- Runs `pending`, sem owner, com snapshot em formato suportado.

O claim muda `pending` para `running`, persiste owner e nova generation e somente depois do commit inicia a árvore local.

A compatibilidade é assimétrica:

- Runs legadas `running` sem snapshot continuam recuperáveis;
- Runs legadas `pending` sem snapshot deixam de ser claimable;
- Runs `running` continuam recuperáveis mesmo sem snapshot ou com formato desconhecido.

Política de rolling upgrade e remoção futura de formatos suportados continua aberta.

## Versionamento e imutabilidade

- formatos novos valem somente para novas Runs;
- snapshot existente não é migrado nem reinterpretado in-place;
- o decoder é selecionado por `format_version`;
- um documento v1 já válido não pode se tornar inválido por endurecimento do mesmo decoder; mudança incompatível exige nova versão;
- Runs existentes podem continuar sem snapshot;
- novas Runs criadas pela API pública sempre possuem snapshot.

## Validação neste slice

A validação inicial é estrutural. Os contexts owners e EnvironmentDeployment agora materializam existência e invariantes locais; a composição semântica cross-context continua responsabilidade do resolver.

O futuro workflow de resolução pertence à orchestration em `leafcutter_runtime`. `Executions.Runs.create/1` recebe uma definition já resolvida; Executions não consulta internals de Catalog, Connections ou Integrations.

## Evolução posterior

Após a materialização deste ADR, o ADR-0018 materializou o Catalog mínimo com PackageVersion, ContractVersion e a topologia relacional de endpoints, seguido por Connections, Integration e EnvironmentDeployment com seus bindings. O formato RunSnapshot v1 permaneceu inalterado. O resolver semântico continua pendente; por isso a consistência cross-context ainda não é comprovada por `Executions.Runs.create/1`.

## Consequências

- uma Run nova nasce com snapshot estruturalmente completo e identificado por versão;
- o PostgreSQL protege atomicidade, unicidade e rejeição de update;
- o formato versionado evita depender de configuração mutável;
- recovery de `pending` deixa de inferir elegibilidade a partir da linha mínima de `Run`;
- Catalog, Connections e Integrations não são antecipados;
- Broadway, Record, Delivery e data plane continuam fora deste slice;
- a futura criação a partir de `EnvironmentDeployment` resolve as authorities upstream fora de Executions e chama a API pública com a definition pronta.

## Fora do escopo

O formato v1 não inclui organization, environment, integration ou deployment ids, revision, actor, invocation, input por Run, idempotency key, artifact digest, retry, batch ou concurrency policy.

Lifecycle completo, terminalização, retenção, autenticação, secrets concretos, rolling upgrade de formatos e carregamento da definição no coordinator continuam decisões ou slices posteriores.

## Alternativas rejeitadas

- armazenar o snapshot como colunas em `runs`;
- dar identidade e lifecycle independentes ao snapshot;
- normalizar o formato v1 em tabelas filhas antes de existir necessidade de query relacional;
- permitir atualização do snapshot;
- criar primeiro Catalog, Connections e Integrations para então definir a fundação;
- tornar Runs `pending` elegíveis sem prova persistida de definição suportada.
