# Modelo conceitual

> **Status: PARCIALMENTE MATERIALIZADO.** As entidades atuais são marcadas separadamente da cadeia executável futura.

## Conceitos materializados

```text
Organization
└── Environment
    ├── Connection
    ├── Secret
    │   └── SecretVersion
    └── EnvironmentDeployment
        └── EnvironmentDeploymentBinding

Organization
└── Integration

User
└── Membership
    └── RoleAssignment

ServiceAccount
└── ServiceAccountRoleAssignment

Role
└── RolePermission

RuntimeNode
└── Run ownership

Run
└── RunSnapshot
```

`Run` existe hoje como identidade de lifecycle e authority de ownership. `RunSnapshot` congela a definition estruturalmente validada e versionada criada com a Run. A resolução semântica upstream a partir de EnvironmentDeployment está materializada; a execução dessa definition ainda não.

## Relação principal planejada

```text
PackageVersion
    │ deployed through
    ▼
EnvironmentDeployment
    │ snapshotted into
    ▼
Run + RunSnapshot
    │ processes
    ▼
Record
    │ fans out into
    ▼
Delivery
    │ attempted through
    ▼
Attempt
```

## Organization e Environment

`Organization` é a fronteira de tenancy. `Environment` é scope operacional configurável. O lifecycle básico e o RBAC desses conceitos estão implementados.

Connections e EnvironmentDeployments já carregam referências explícitas de Organization/Environment. Runs e IdentityMappings receberão scope explícito conforme seu ownership e os slices ratificados.

## Catalog

O Catalog ratificado controla identidade, metadata, publicação e versões imutáveis de:

```text
Connector
ConnectorVersion
Operation metadata
Contract
ContractVersion
Package
PackageVersion
```

O modelo mínimo de publicação e a projeção relacional de PackageVersion endpoints foram ratificados no ADR-0018. Connector, ConnectorVersion e Operation estão materializados com publicação atômica e sealing no PostgreSQL. Contract e ContractVersion materializam identities publicadas e imutáveis; novas versões também persistem schema Draft 2020-12 object/boolean validado e construído com JSV. Package, PackageVersion e seus endpoints relacionais completam o Catalog mínimo com cardinalidade, referências, ordem e imutabilidade protegidas no banco; novas PackageVersions rejeitam ContractVersions identity-only legadas.

O ADR-0019 está parcialmente materializado: publicação executável, `Contracts.compile/1`, `Contracts.validate/2` e a proteção em PackageVersion existem; a propagação por EnvironmentDeployment e pela resolução de Run permanece pendente. Schema continua owned pelo Catalog e RunSnapshot v1 continua referenciando somente `contract_version_id`.

## Connections

O modelo mínimo ratificado está materializado:

```text
Environment
├── Connection
│   ├── stable Connector reference
│   ├── non-sensitive config
│   └── optional exact SecretVersion binding
└── Secret
    └── immutable SecretVersion
```

Connection pode alterar somente config e binding para resoluções futuras; disable é idempotente. Organization e Environment ativos são validados sob locks compartilhados. SecretVersion não contém material secreto e permanece imutável. Provider, encryption, OAuth, rotation, revocation e retention continuam posteriores.

## Integration e EnvironmentDeployment

`Integration` é uma identidade lógica materializada de uma Organization vinculada a um Package estável. Seu lifecycle mínimo expõe create, get, disable e lock ativo para workflows compostos.

O modelo mínimo ratificado está materializado e usa no máximo um EnvironmentDeployment por Integration e Environment. O deployment guarda estado executável atual e mutável:

- PackageVersion;
- source/destination Connection bindings por ref;
- promotable config;
- local config.

Create e replace persistem o estado completo e todos os bindings atomicamente. O banco protege identidade, JSON objects, PackageVersion compatível, cobertura exata de endpoints e compatibilidade de Connector. Triggers, revision, history, promotion e lifecycle independente do deployment permanecem futuros.

## Run e RunSnapshot

Hoje `Run` possui status, owner, generation e timestamps de ownership. Novas Runs criadas pela API pública possuem uma relação 1:1 com `RunSnapshot` imutável:

```text
resolved PackageVersion
+ ContractVersions
+ effective config
+ Connection references
+ safe SecretVersion references
= immutable RunSnapshot
```

Runs legadas podem não possuir snapshot. Runs `pending` só são elegíveis no control plane quando possuem snapshot em formato suportado.

Raw secrets permanecem fora do snapshot. O resolver transacional materializado pelo ADR-0018 congela Connection config, SecretVersion bindings e effective config sem adicionar provenance IDs ao formato v1.

## Record, Delivery e Attempt

Futuro ratificado:

```text
Record
→ ocorrência de um item da origem dentro de uma Run

Delivery
→ obrigação durável de processar o Record para um destino

Attempt
→ tentativa concreta de efeito externo
```

## Identity

```text
Record ID
→ ocorrência interna

SourceIdentity
→ identidade estável na origem

PayloadHash
→ fingerprint do conteúdo

IdentityMapping
→ relação persistente entre identidades de sistemas diferentes
```

## Checkpoint

Checkpoint será o último progresso seguro do source. Seu avanço será atômico com a criação de Records e Deliveries.

## Eventos

Planejado:

```text
ExecutionEvent
→ lifecycle da execução

AuditEvent
→ ações humanas/administrativas

PubSub message
→ propagação efêmera, nunca authority
```
