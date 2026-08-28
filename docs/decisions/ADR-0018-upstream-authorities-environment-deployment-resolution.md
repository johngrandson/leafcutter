# ADR-0018 — Authorities upstream mínimas e resolução de EnvironmentDeployment

- Status: Proposed
- Estado de implementação: NÃO MATERIALIZADO
- Data: 2026-08-28

## Contexto

RunSnapshot v1 já materializa o destino estrutural, versionado e imutável de uma resolução executável. A próxima fronteira precisa persistir as authorities mínimas de Catalog, Connections e Integrations e compô-las em `leafcutter_runtime` sem antecipar Package Manifest, data plane ou secrets concretos.

Os schemas, APIs e a semântica do resolver continuam abertos em `docs/architecture/decisoes-em-aberto.md`. Este ADR permanece `Proposed` até que o contract completo do slice seja ratificado.

## Decisão aprovada até agora

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

## Decisões ainda pendentes neste ADR

- lifecycle e APIs mínimas das versões do Catalog;
- schemas e invariantes mínimos de Connection, Secret e SecretVersion;
- schemas e lifecycle mínimos de Integration e EnvironmentDeployment;
- representação dos bindings entre endpoints e Connections;
- merge e precedence de config não sensível;
- consistência transacional da resolução;
- contrato público e erros de `create_from_deployment/1`;
- comportamento de chamadas repetidas e fronteira de idempotency.

Nenhuma migration ou API relativa a essas decisões deve ser implementada enquanto elas permanecerem abertas.

## Alternativas consideradas para a topologia

### Definition JSONB dentro de PackageVersion

Rejeitada para este slice porque criaria um segundo document contract antes da ratificação do Package Manifest e reduziria a capacidade do banco de proteger referências e cardinalidade.

### Usar diretamente o Package Manifest como persistência

Rejeitada porque `package-manifest-v1.md` continua DRAFT e seus field names não são canônicos.

### Duplicar ConnectorVersion no endpoint

Rejeitada porque `Operation` já pertence a uma ConnectorVersion. A duplicação criaria duas referências que poderiam divergir.

## Estado atual

Materializado:

- `Run` e `RunSnapshot`;
- `RunSnapshot.DefinitionV1`;
- criação atômica por `Executions.Runs.create/1`;
- eligibility e recovery de Runs `pending` com formato suportado.

Não materializado:

- Catalog;
- Connections;
- Integrations;
- resolver de EnvironmentDeployment.

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

## Consequências

- Catalog poderá validar a topologia sem transformar o manifest aberto em contract persistido;
- o resolver obterá refs, Operations e ContractVersions por uma API pública do owner;
- referências relacionais e cardinalidade poderão ser protegidas antes da criação da Run;
- a ingestão futura de packages precisará traduzir o manifest para a projeção interna;
- o ADR precisa continuar evoluindo de forma explícita até a ratificação completa.

## Evidência

- `docs/decisions/ADR-0017-run-snapshot-v1.md`;
- `docs/specifications/run-snapshot-v1.md`;
- `docs/architecture/contextos-e-ownership.md`;
- `docs/architecture/modelo-conceitual.md`;
- `docs/architecture/integration-packages.md`;
- `docs/specifications/package-manifest-v1.md`;
- `docs/checkpoint/CURRENT.md`.
