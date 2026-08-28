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

## Decisões ainda pendentes neste ADR

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
