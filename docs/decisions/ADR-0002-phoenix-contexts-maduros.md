# ADR-0002 — Phoenix Contexts maduros e APIs segmentadas

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO

## Decisão

Contexts representam boundaries de domínio e podem expor facade raiz, capability modules e internals privados.

## Estado atual

`Organizations` está materializado com capabilities de Environments, Users, ServiceAccounts, Roles e Access. `Executions` possui foundation de RuntimeNode, Run, RunSnapshot, ownership e recovery. `Catalog` possui Connector, ConnectorVersion, Operation, Contract, ContractVersion, Package, PackageVersion e PackageVersionEndpoint materializados. `Connections` possui Connection, Secret e SecretVersion com APIs segmentadas e integridade de scope. `Integrations` possui Integration, EnvironmentDeployment, bindings e lifecycle mínimo em facade e capability module separados.

Availability/deprecation do Catalog, OAuth/rotation e secret providers de Connections,
promotion/homologation de Integrations, Notifications e Audit permanecem ratificados, mas não
materializados. Manifest/binding, digest, build inventory, release closure e resolução
compilada foram materializados em 26C2 sob os respectivos owners.

## Consequências

- outros contexts não acessam schemas/queries internos;
- referência por ID não cria dependência de API;
- composição cross-context pertence à application layer;
- context não é sinônimo de arquivo nem tabela.
