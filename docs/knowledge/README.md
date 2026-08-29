---
type: schema
updated: 2026-08-29
---
# Base de conhecimento local

## Propósito

Esta base registra sínteses, gotchas e pins locais derivados das fontes
canônicas do Leafcutter. Ela reduz redescoberta durante o trabalho, mas não
cria autoridade paralela nem substitui uma fonte canônica.

## Autoridade e conflitos

A ordem completa de autoridade é:

```text
Código + testes
    ↓
ADRs aceitos
    ↓
Documentação arquitetural ratificada
    ↓
Specifications e OpenAPI versionados
    ↓
CURRENT.md para o ponto de continuidade
    ↓
Base de conhecimento DERIVADA
    ↓
Research e conversas como apoio
```

`DERIVADA` classifica a autoridade desta camada. Não é um novo estado de
implementação e não altera o vocabulário de ADR-0016. Em qualquer conflito,
retorne à fonte canônica, corrija a entrada derivada após revisão e registre a
mutação em `log.md` quando aplicável.

## Camadas

- `syntheses.md`, `gotchas.md` e `pins.md`: entradas ativas derivadas.
- `raw/`: fontes humanas imutáveis, usadas como evidência.
- `proposals/`: candidatos ainda não aprovados.
- `log.md`: registro de mutações aprovadas; não é fonte para consultas.

## Tipos de entrada

Use `SYN-` para sínteses, `G-` para gotchas e `PIN-` para pins. Cada entrada
ativa deve identificar seu contexto, estado e fonte de autoridade ou
evidência. Os formatos abaixo são exemplos do schema, não entradas ativas.

### Síntese

```markdown
## SYN-runtime-run-recovery
- Contexto: Executions
- Síntese: RunRecovery recupera ownership durável; Registry permanece local.
- Autoridade: `docs/decisions/ADR-0011-run-ownership-fencing.md`
- Evidência: `apps/leafcutter_runtime/test/leafcutter_runtime/run_recovery_test.exs`
- Estado: derivado
```

### Gotcha

```markdown
## G-integrations-deployment-lock-order
- Contexto: Integrations
- Situação: resolução concorrente com replace de deployment.
- Risco: leitura híbrida das authorities mutáveis.
- Conduta: respeitar a ordem de locks ratificada no ADR-0018.
- Evidência: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`
- Estado: confirmado
```

### Pin

```markdown
## PIN-snapshot-authority
- Intenção: RunSnapshot não cria authority paralela para PackageVersion.
- Escopo: Executions e Catalog.
- Autoridade relacionada: `docs/specifications/run-snapshot-v1.md`
- Estado: ativo
```

## Provenance

Cada claim deve apontar para paths versionados, fonte humana versionada em
`raw/` ou evidência reproduzível. Fontes não versionáveis não são aceitas. A
entrada descreve a derivação e nunca amplia a semântica da fonte. Ausência de
evidência suficiente exige proposta ou pedido de esclarecimento, não uma
entrada ativa.

## Operações de consulta, ingestão, captura e lint

- Consulta: comece em `INDEX.md`, leia as fontes canônicas indicadas e
  carregue somente os arquivos ativos marcados como relevantes para o contexto.
- Ingestão: humanos adicionam uma nova fonte em `raw/`; fontes existentes não
  são alteradas.
- Captura: agentes podem redigir candidatos em `proposals/` somente após pedido
  explícito; uma aprovação humana é necessária antes da promoção.
- Lint: `python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict` apenas
  relata achados e não modifica arquivos.

## Política de escrita e revisão

Agentes não criam facts ativos por inferência. Toda escrita por agente exige
pedido explícito do usuário ou aprovação humana explícita antes da ação,
inclusive criar, editar, remover ou promover entradas ativas. Alterações em
sínteses, gotchas e pins exigem evidência rastreável. Pins provocam
reconciliação; não prevalecem sobre código, testes, ADRs, specifications ou
`CURRENT.md`.

## Segurança e privacidade

Não registrar segredos, credenciais, tokens, ciphertext, dados pessoais ou
payloads de clientes, ainda que não sensíveis. Referencie paths e
identificadores mínimos necessários. Redações e correções são adicionadas como
novos arquivos em `raw/`, preservando a fonte original.

## Critérios para dividir arquivos

Mantenha cada arquivo ativo focado em um tipo de entrada e com até 200 linhas.
Divida por context ou capacidade ratificada quando a rota deixar de ser clara;
atualize `INDEX.md` e preserve links de provenance. Não crie topologia de
múltiplos projetos, camadas globais ou abstrações antes de existir necessidade.

Os workflows de extração e consolidação podem voltar quando houver uma extração
explicitamente solicitada ou arquivos ativos acima de 200 linhas.
