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
24. resolver scope discovery without binding reads
25. EnvironmentDeployment transactional resolver
26. executable ContractVersion/JSV contract ratification (frontier Slice 26A)
27. executable ContractVersion/JSV materialization through PackageVersion
→ ContractVersion schema JSONB object/boolean
→ publication-time Draft 2020-12 validation + JSV build
→ Contracts.compile/1 + validate/2
→ PackageVersion legacy executability check
→ RunSnapshot v1 unchanged
```

## Próximas etapas do Slice 26A

```text
28. reject legacy ContractVersions in EnvironmentDeployment create/replace
29. repeat the executability check in EnvironmentDeployment → Run resolution
```

O estágio upstream completo foi materializado conforme o ADR-0018 e `docs/specifications/environment-deployment-run-resolution.md`. O contrato exato do Slice 26A foi ratificado no ADR-0019 e em `docs/specifications/contract-version-execution.md`; sua materialização alcança hoje PackageVersion. O restante deve permanecer restrito a esse documento; Operation e HTTP não entram no mesmo slice.

## Sequência ratificada posterior

```text
minimal Catalog authorities (materialized)
→ Connections + SecretVersion bindings (materialized)
→ Integration identity (materialized)
→ EnvironmentDeployment + bindings (materialized)
→ EnvironmentDeployment resolver (materialized)
→ ContractVersion executable + JSON Schema/JSV through PackageVersion (26A, materialized)
→ EnvironmentDeployment + Run executability propagation (26A, pending)
→ Operation executable contracts (26B, pending ratification)
→ HTTP Transport + reference Operation (26C, pending ratification)
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem dos cinco primeiros sub-slices foi concluída conforme o ADR-0018. O Slice 26A deve completar e provar a propagação por Deployment e Run antes da ratificação concreta de 26B/26C. A sequência posterior não deve criar Broadway com definição implícita.
