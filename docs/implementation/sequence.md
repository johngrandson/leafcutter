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

## Etapas concluídas do Slice 26A

```text
28. reject legacy ContractVersions in EnvironmentDeployment create/replace
29. repeat the executability check in EnvironmentDeployment → Run resolution
```

O estágio upstream completo foi materializado conforme o ADR-0018 e `docs/specifications/environment-deployment-run-resolution.md`. O contrato exato do Slice 26A foi ratificado no ADR-0019 e em `docs/specifications/contract-version-execution.md`; sua materialização alcança PackageVersion, EnvironmentDeployment e resolução de Run.

## Etapas concluídas do Slice 26B

~~~text
30. executable Operation contract ratification
31. executable Operation boundary materialization
→ shared JSON-compatible types and normalized error
→ Read/Write behaviours and invocation/result structs
→ opaque JSON cursor with nil terminal state
→ complete ordered per-item Write results
→ credentials redaction and pure invariant validation
→ no Transport or runtime materialization
~~~

O ADR-0021 e `docs/specifications/operation-contract.md` controlam o contract concreto. HTTP não entra no mesmo slice.

## Etapa materializada do Slice 26C1

~~~text
32. HTTP Transport contract and Slice 26C sequencing ratification
33. HTTP Transport boundary materialization
→ HTTP-specific facade and Adapter behaviour
→ bounded Request/Response/Error values
→ one-attempt Finch HTTP/1 adapter and supervised pool
→ deterministic local conformance tests
→ no Package Manifest, module resolution or reference Operation
~~~

O ADR-0022 e `docs/specifications/http-transport.md` controlam 26C1 materializado. Os
incrementos 26C2 e 26C3 permanecem separados e não podem ser substituídos por registry temporário.

## Sequência ratificada posterior

```text
minimal Catalog authorities (materialized)
→ Connections + SecretVersion bindings (materialized)
→ Integration identity (materialized)
→ EnvironmentDeployment + bindings (materialized)
→ EnvironmentDeployment resolver (materialized)
→ ContractVersion executable + JSON Schema/JSV through PackageVersion/Deployment/Run (26A, materialized)
→ Operation executable contract (26B, materialized)
→ HTTP Transport boundary + Finch adapter (26C1, materialized)
→ Package Manifest/build binding + module resolution (26C2, pending ratification)
→ first production HTTP Operation (26C3, pending ratification)
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem upstream foi concluída conforme o ADR-0018, o Slice 26A completou a propagação por Deployment e Run, o Slice 26B materializou a boundary de Operation e 26C1 materializou o Transport HTTP. A próxima etapa ratifica 26C2. 26C2/26C3 preservam Package Manifest, module resolution e a referência real para decisões próprias. A sequência posterior não deve criar Broadway com definição implícita.
