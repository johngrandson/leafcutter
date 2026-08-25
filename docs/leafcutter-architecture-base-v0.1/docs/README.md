# Índice da documentação do Leafcutter

## Arquitetura

- `architecture/como-o-leafcutter-foi-arquitetado.md`: narrativa geral da arquitetura.
- `architecture/principios-e-restricoes.md`: critérios obrigatórios de design.
- `architecture/visao-geral.md`: visão resumida das peças.
- `architecture/modelo-conceitual.md`: relações entre Package, Integration, Run e dados de execução.
- `architecture/contextos-e-ownership.md`: proposta de Phoenix Contexts e ownership.
- `architecture/umbrella-e-dependencias.md`: proposta de apps e grafo de dependências.
- `architecture/integration-packages.md`: estrutura de packages.
- `architecture/contracts-json-schema.md`: contratos e JSV.
- `architecture/connectors-operations-transports.md`: integração com sistemas externos.
- `architecture/transformations-enrichments-interceptors.md`: lógica customizada.
- `architecture/runtime-otp-broadway.md`: control plane e data plane.
- `architecture/durabilidade-e-recovery.md`: Postgres, checkpoints e `at-least-once`.
- `architecture/cluster-e-infraestrutura.md`: nodes BEAM e evolução da infraestrutura.
- `architecture/api-openapi.md`: API-first, OpenAPI e Postman.
- `architecture/ambientes-rbac-homologacao.md`: governança.
- `architecture/observabilidade-e-auditoria.md`: monitoramento e eventos.
- `architecture/storage-e-retencao.md`: lifecycle de metadata e payloads.
- `architecture/testes-e-qualidade.md`: estratégia de qualidade.
- `architecture/roadmap.md`: releases planejadas.
- `architecture/decisoes-em-aberto.md`: pontos ainda não ratificados.
- `architecture/glossario.md`: linguagem oficial do produto.

## Decisões

Consulte `decisions/README.md`.

## Harness

- `harness/CODEX_OPERATING_MODEL.md`
- `harness/SESSION_HANDOFF.md`
- `harness/TASK_BRIEF_TEMPLATE.md`
- `harness/REVIEW_CHECKLIST.md`
- `harness/CHANGE_PROTOCOL.md`

## Implementação

- `implementation/sequence.md`
- `implementation/first-milestone.md`
- `implementation/definition-of-done.md`
- `implementation/quality-gates.md`

## Checkpoint

- `checkpoint/CURRENT.md`
- `checkpoint/SESSION_BOOTSTRAP.md`
