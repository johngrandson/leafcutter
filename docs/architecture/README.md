# Índice da arquitetura

Esta pasta contém tanto a arquitetura **já materializada** quanto a arquitetura **ratificada para os próximos estágios**. Nenhum diagrama futuro deve ser lido como descrição do código atual sem a indicação correspondente.

## Documentos canônicos

| Documento | Estado principal | Uso |
|---|---|---|
| `estado-atual-e-visao-futura.md` | MATERIALIZADO + FUTURO | Matriz canônica entre código atual, direção ratificada e decisões abertas. |
| `visao-geral.md` | PARCIALMENTE MATERIALIZADO | Visão curta do sistema presente e da plataforma-alvo. |
| `como-o-leafcutter-foi-arquitetado.md` | PARCIALMENTE MATERIALIZADO | Narrativa longa das escolhas e da evolução planejada. |
| `principios-e-restricoes.md` | RATIFICADO | Regras que valem para implementação atual e futura. |
| `contextos-e-ownership.md` | PARCIALMENTE MATERIALIZADO | Context Map ratificado e estado de cada context. |
| `umbrella-e-dependencias.md` | MATERIALIZADO + FUTURO | Apps existentes, grafo real e composição futura da release. |
| `runtime-otp-broadway.md` | PARCIALMENTE MATERIALIZADO | Control plane atual e data plane Broadway planejado. |
| `durabilidade-e-recovery.md` | PARCIALMENTE MATERIALIZADO | Liveness/ownership/recovery atuais e durable fan-out futuro. |
| `ambientes-rbac-homologacao.md` | PARCIALMENTE MATERIALIZADO | RBAC existente e governança futura. |
| `modelo-conceitual.md` | PARCIALMENTE MATERIALIZADO | Entidades atuais e cadeia completa planejada. |

## Documentos de capacidades parciais ou futuras ratificadas

| Documento | Estado |
|---|---|
| `connectors-operations-transports.md` | METADATA MATERIALIZADA; SLICES 26B/26C ABERTOS |
| `contracts-json-schema.md` | IDENTIDADE MATERIALIZADA; SLICE 26A RATIFICADO |
| `integration-packages.md` | PARCIALMENTE MATERIALIZADO |
| `transformations-enrichments-interceptors.md` | RATIFICADO — NÃO MATERIALIZADO |
| `api-openapi.md` | PARCIALMENTE MATERIALIZADO |
| `observabilidade-e-auditoria.md` | PARCIALMENTE MATERIALIZADO |
| `storage-e-retencao.md` | PARCIALMENTE MATERIALIZADO |

## Operação, evolução e referência

| Documento | Estado |
|---|---|
| `cluster-e-infraestrutura.md` | PARCIALMENTE MATERIALIZADO |
| `testes-e-qualidade.md` | MATERIALIZADO + EVOLUÇÃO |
| `roadmap.md` | PLANEJAMENTO |
| `decisoes-em-aberto.md` | ABERTO |
| `glossario.md` | CANÔNICO |

## Regra de manutenção

Ao materializar uma parte planejada:

1. atualizar o código e os testes;
2. atualizar o ADR relacionado, indicando o novo estado de implementação;
3. mover a capacidade da seção futura para a seção materializada no documento correspondente;
4. atualizar `checkpoint/CURRENT.md`;
5. manter no mesmo documento a visão posterior que ainda continua válida.

Não apagar a arquitetura futura apenas porque o slice atual é menor. Também não apresentar a arquitetura futura como se ela já existisse no código.
