# ADR-0002 — Phoenix Contexts maduros e APIs segmentadas

- Status: Accepted
- Estado de implementação: PARCIALMENTE MATERIALIZADO

## Decisão

Contexts representam boundaries de domínio e podem expor facade raiz, capability modules e internals privados.

## Estado atual

`Organizations` está materializado com capabilities de Environments, Users, ServiceAccounts, Roles e Access. `Executions` possui foundation de RuntimeNode, Run, RunSnapshot, ownership e recovery. `Catalog` possui Connector, ConnectorVersion, Operation, Contract, ContractVersion, Package, PackageVersion e PackageVersionEndpoint materializados. `Connections` possui Connection, Secret e SecretVersion com APIs segmentadas e integridade de scope.

Availability e manifest/build do Catalog, OAuth/rotation e secret providers de Connections, Integrations, Notifications e Audit permanecem ratificados, mas não materializados.

## Consequências

- outros contexts não acessam schemas/queries internos;
- referência por ID não cria dependência de API;
- composição cross-context pertence à application layer;
- context não é sinônimo de arquivo nem tabela.

