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
```

## Próximo slice

```text
Catalog authorities mínimas
+ Connections e SecretVersion bindings mínimos
+ Integration e EnvironmentDeployment persistidos
→ resolver definition v1 em leafcutter_runtime
→ Executions.Runs.create/1
```

Ownership, schemas e APIs mínimas desses contexts precisam ser ratificados antes da implementação. O contrato de destino já materializado está em `docs/decisions/ADR-0017-run-snapshot-v1.md` e `docs/specifications/run-snapshot-v1.md`.

## Sequência ratificada posterior

```text
Catalog/Contracts/Packages foundations
→ Connections/Secrets
→ Integrations/EnvironmentDeployment
→ EnvironmentDeployment resolver
→ Connector/Operation/Transport
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem fina pode mudar quando dependencies reais forem modeladas. O próximo slice não deve antecipar schemas upstream. A sequência posterior não deve pular a resolução executável de RunSnapshot para criar Broadway com definição implícita.
