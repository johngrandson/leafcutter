# Sequência de implementação

## Regra

Não criar todas as apps, contexts e schemas de uma vez. Implementar verticalmente, preservando boundaries ratificados.

## Sequência recomendada

1. Ratificar Context Map.
2. Ratificar apps da umbrella.
3. Criar `leafcutter_core` mínimo e Repo.
4. Criar Organizations/Environments mínimos.
5. Criar Catalog Contracts + JSV spike.
6. Fechar Package Manifest v1 e validation tooling.
7. Criar Connections/Secrets baseline.
8. Criar Integrations e Run Snapshot.
9. Criar Executions durable model.
10. Criar Generic HTTP Connector e Operation contracts.
11. Criar Source Broadway com persistence batch/checkpoint.
12. Criar Destination Broadway com claim/transform/validate/deliver.
13. Criar Attempts, retries e IdentityMapping.
14. Expor workflow por OpenAPI/API.
15. Adicionar schedules, Enrichment e cluster recovery.
16. Adicionar governance conforme roadmap.

Cada etapa deve produzir algo testável e documentado.
