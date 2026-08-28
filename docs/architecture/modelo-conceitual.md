# Modelo conceitual

> **Status: PARCIALMENTE MATERIALIZADO.** As entidades atuais são marcadas separadamente da cadeia executável futura.

## Conceitos materializados

```text
Organization
└── Environment

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

`Run` existe hoje como identidade de lifecycle e authority de ownership. `RunSnapshot` congela a definition estruturalmente validada e versionada criada com a Run; a resolução semântica upstream e a execução dessa definition ainda não estão materializadas.

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

No futuro, Connections, EnvironmentDeployments, Runs e IdentityMappings carregarão referências explícitas de Organization/Environment conforme seu ownership.

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

Ainda não existe implementação do Catalog.

## Integration e EnvironmentDeployment

`Integration` será identidade lógica de uma Organization vinculada a um Package estável.

`EnvironmentDeployment` será a configuração executável por Environment:

- PackageVersion;
- source/destination Connection bindings;
- promotable config;
- local config;
- Triggers;
- lifecycle.

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

Raw secrets permanecem fora do snapshot.

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
