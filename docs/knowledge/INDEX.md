---
type: router
updated: 2026-08-29
---
# Base de conhecimento — índice

Esta base atende a um único projeto: Leafcutter. Para cada tarefa, consulte
primeiro as fontes canônicas do context e carregue somente os arquivos
derivados que o resumo do context indicar como relevantes. `raw/`,
`proposals/` e `log.md` não participam de consultas normais.

## Roteamento por context

### Organizations

- Fontes canônicas: `docs/architecture/contextos-e-ownership.md` e
  `docs/checkpoint/CURRENT.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente para tenancy,
  Environment, acesso e RBAC relevantes.

### Catalog

- Fontes canônicas: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`
  e `docs/specifications/environment-deployment-run-resolution.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente para Connector,
  Contract, Package ou versões relevantes.

### Connections

- Fontes canônicas: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`
  e `docs/architecture/contextos-e-ownership.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente para Connection,
  Secret ou SecretVersion relevantes.

### Integrations

- Fontes canônicas: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`
  e `docs/specifications/environment-deployment-run-resolution.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente para Integration,
  EnvironmentDeployment ou bindings relevantes.

### Executions e runtime

- Fontes canônicas: `docs/decisions/ADR-0011-run-ownership-fencing.md`,
  `docs/decisions/ADR-0017-run-snapshot-v1.md` e
  `docs/specifications/run-ownership.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente para Run,
  RunSnapshot, ownership, recovery ou runtime relevantes.

### Notifications

- Fontes canônicas: `docs/architecture/contextos-e-ownership.md` e
  `docs/architecture/decisoes-em-aberto.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente quando a tarefa
  tratar da capacidade ratificada ainda não materializada.

### Audit

- Fontes canônicas: `docs/architecture/contextos-e-ownership.md` e
  `docs/architecture/decisoes-em-aberto.md`.
- Derivados: `syntheses.md`, `gotchas.md` ou `pins.md` somente quando a tarefa
  tratar do sink append-only ratificado ainda não materializado.

## Manutenção

Consulte o schema em `README.md` antes de escrever. O lint estrito é
`python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict` e apenas
reporta achados.
