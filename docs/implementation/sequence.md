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
```

## Próximo slice

```text
RunSnapshot
+
public Run creation workflow
+
pending eligibility
```

## Sequência ratificada posterior

```text
Catalog/Contracts/Packages foundations
→ Connections/Secrets
→ Integrations/EnvironmentDeployment
→ complete executable RunSnapshot
→ Connector/Operation/Transport
→ Record/Delivery/Attempt/Checkpoint
→ Source/Destination Broadway
→ monitoring/retry/lifecycle
→ governance/notifications/audit
```

A ordem fina pode mudar quando dependencies reais forem modeladas. Não pular RunSnapshot para criar Broadway com definição executável implícita.
