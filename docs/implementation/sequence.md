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
```

## Próximo slice

```text
RunSnapshot v1 persistence + immutability
+
typed definition validation
+
public Run creation and snapshot fetch
+
pending eligibility in claim and recovery
```

O contrato deste slice está em `docs/decisions/ADR-0017-run-snapshot-v1.md` e `docs/specifications/run-snapshot-v1.md`.

## Sequência ratificada posterior

```text
Catalog/Contracts/Packages foundations
→ Connections/Secrets
→ Integrations/EnvironmentDeployment
→ EnvironmentDeployment resolver
→ semantically resolved executable RunSnapshot
→ Connector/Operation/Transport
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem fina pode mudar quando dependencies reais forem modeladas. O próximo slice não deve antecipar schemas upstream. A sequência posterior não deve pular a resolução executável de RunSnapshot para criar Broadway com definição implícita.
