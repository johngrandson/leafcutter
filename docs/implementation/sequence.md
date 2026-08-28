# Sequência de implementação

## Concluído

```text
1. architecture/context map
2. four OTP applications
3. shared Repo + PubSub + Oban
4. Organizations + Environment
5. User + Membership
6. Role + Permission
7. User/ServiceAccount role assignments
8. authorization evaluation
9. Registry + DynamicSupervisor + NodeHeartbeat
10. durable RuntimeNode liveness
11. Run ownership + generation fencing
12. RunSupervisor + RunCoordinator
13. automatic RunRecovery
14. documentation present/future alignment
15. RunSnapshot v1 contract ratification
16. RunSnapshot v1 materialization
17. Catalog Connector/ConnectorVersion/Operation materialization
```

## Próximo slice de implementação

```text
Contract + ContractVersion
Package + PackageVersion + PackageVersionEndpoint
→ publicação atômica
→ versões imutáveis
```

O contract do estágio upstream completo foi ratificado no ADR-0018 e em `docs/specifications/environment-deployment-run-resolution.md`. Connector authorities já estão materializadas. O próximo sub-slice completa somente Catalog; Connections, Integrations e o resolver permanecem posteriores.

## Sequência ratificada posterior

```text
remaining Catalog authorities
→ Connections + SecretVersion bindings
→ Integration + EnvironmentDeployment
→ EnvironmentDeployment resolver
→ Contracts/JSV + Connector/Operation/Transport
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem dos quatro primeiros sub-slices está ratificada pelo ADR-0018. A sequência posterior não deve pular a resolução executável de RunSnapshot para criar Broadway com definição implícita.
