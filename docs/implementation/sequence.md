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
18. Catalog Contract/ContractVersion materialization
19. Catalog Package/PackageVersion/PackageVersionEndpoint materialization
20. Connections/Secret/SecretVersion materialization
21. Integration identity materialization
22. EnvironmentDeployment/EnvironmentDeploymentBinding materialization
23. resolver-facing deployment lock and SecretVersion reads
```

## Próximo slice de implementação

```text
LeafcutterRuntime.Runs.create_from_deployment/1
→ resolve authorities upstream em uma transação
→ congela definition v1
→ Executions.Runs.create/1
```

O contract do estágio upstream completo foi ratificado no ADR-0018 e em `docs/specifications/environment-deployment-run-resolution.md`. Todas as authorities upstream mínimas estão materializadas. O próximo sub-slice implementa o resolver transacional sem ampliar o formato RunSnapshot v1.

## Sequência ratificada posterior

```text
minimal Catalog authorities (materialized)
→ Connections + SecretVersion bindings (materialized)
→ Integration identity (materialized)
→ EnvironmentDeployment + bindings (materialized)
→ EnvironmentDeployment resolver
→ Contracts/JSV + Connector/Operation/Transport
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem dos cinco primeiros sub-slices está ratificada pelo ADR-0018. A sequência posterior não deve pular a resolução executável de RunSnapshot para criar Broadway com definição implícita.
