# Contrato de qualidade H0: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidar a documentação dos quality gates e tornar `mix quality`
uma obrigação manual antes de cada commit.

**Architecture:** `mix.exs` continua definindo o alias executável, enquanto
`docs/implementation/quality-gates.md` concentra sua descrição operacional.
Documentos de arquitetura e do harness apontam para essas fontes sem copiar
listas que possam divergir. O ADR-0015 registra a evolução do contrato, sem
afirmar que pre-commit ou CI já existem.

**Tech Stack:** Markdown, Git, Mix.

**Spec:** `docs/harness/specifications/H0-quality-contract.md`.

## Global Constraints

- Escrever o conteúdo específico do projeto em português brasileiro. Manter o
  cabeçalho de execução exigido por este formato de plano.
- Não alterar `mix.exs`, código, testes, hooks, CI ou a base de conhecimento.
- Não alterar `docs/checkpoint/CURRENT.md` nem documentação de produto fora
  de `docs/architecture/testes-e-qualidade.md`.
- Preservar mudanças preexistentes no working tree e fazer stage por path
  explícito.
- Se o index já contiver mudanças alheias à task, parar e pedir ao desenvolvedor
  para liberar o index. Não remover nem commitar stage alheio.
- Manter `mix.exs` como descrição executável do alias.
- Manter `AGENTS.md` como única ordem de leitura canônica.
- Não declarar hook Git ou CI como materializados.
- Executar `mix quality` antes de cada commit deste plano.

---

### Task 1: Definir o contrato canônico antes do commit

**Files:**

- Modify: `docs/implementation/quality-gates.md:1-61`
- Modify: `docs/decisions/ADR-0015-harness-multi-agente.md:6-16`
- Test: nenhum arquivo novo; usar as verificações read-only desta task

**Interfaces:**

- Consumes: alias `quality` definido em `mix.exs` e obrigações de `AGENTS.md`
- Produces: descrição operacional canônica e evolução normativa do ADR-0015

- [ ] **Step 1: Provar que a obrigação antes do commit ainda está ausente**

Run:

```bash
rg -n '^Antes de cada commit, execute o gate completo\.$' \
  docs/implementation/quality-gates.md
rg -n '^## Evolução: gate compartilhado antes do commit$' \
  docs/decisions/ADR-0015-harness-multi-agente.md
```

Expected: os dois comandos saem com status 1 e sem output.

- [ ] **Step 2: Tornar `quality-gates.md` a descrição operacional canônica**

Adicionar depois do título:

```markdown
`mix.exs` define o comportamento executável do gate. Este documento é sua
descrição operacional canônica para pessoas e agentes.
```

Manter a lista atual de comandos sem adição ou remoção. Depois da explicação
do linter da knowledge base, adicionar:

```markdown
Esses comandos formam o enforcement automático materializado. Reviews humanos
continuam responsáveis pelas regras que não possuem checker objetivo.
```

Depois do bloco de checks focados, substituir a frase sobre merge por:

```markdown
Checks focados reduzem o tempo de feedback. Eles não substituem o gate
agregado.

Antes de cada commit, execute o gate completo.
```

Renomear `Verificações documentais` para `Verificações manuais de review` e
usar esta lista:

```text
decisões ratificadas e escopo autorizado
ownership e APIs públicas entre contexts
necessidade de processos OTP e abstrações
CURRENT.md e estado atual/visão futura
ADR, specification e contracts afetados
exposição de segredos ou dados sensíveis
```

Finalizar a seção com:

```markdown
O checklist detalhado está em `docs/harness/REVIEW_CHECKLIST.md`.
```

- [ ] **Step 3: Registrar a evolução no ADR-0015**

Adicionar depois de `Consequências`:

```markdown
## Evolução: gate compartilhado antes do commit

Em 2026-08-30, o contrato do harness passou a tratar `mix quality` como o gate
compartilhado entre pessoas e agentes. Checks focados podem antecipar feedback,
mas o autor executa o gate completo antes de cada commit.

`mix.exs` define o alias executável e
`docs/implementation/quality-gates.md` mantém sua descrição operacional. A
automação por pre-commit e CI permanece planejada na trilha alternativa de
quality enforcement. Este incremento documenta a obrigação manual e não
declara esses mecanismos como materializados.
```

- [ ] **Step 4: Verificar o contrato canônico**

Run:

```bash
rg -n '^Antes de cada commit, execute o gate completo\.$' \
  docs/implementation/quality-gates.md
rg -n '^## Evolução: gate compartilhado antes do commit$' \
  docs/decisions/ADR-0015-harness-multi-agente.md
git diff --check -- docs/implementation/quality-gates.md \
  docs/decisions/ADR-0015-harness-multi-agente.md
mix quality
```

Expected: cada `rg` encontra uma linha, `git diff --check` sai com status 0 e
`mix quality` termina com status 0. Todas as suítes reportam zero failures, o
Credo não encontra issues e o Dialyzer termina sem erros ou skips.

- [ ] **Step 5: Commitar o contrato canônico**

```bash
test -z "$(git diff --cached --name-only)"
git add docs/implementation/quality-gates.md \
  docs/decisions/ADR-0015-harness-multi-agente.md
test "$(git diff --cached --name-only | wc -l)" -eq 2
git diff --cached --check
git commit -m "docs: define pre-commit quality contract"
```

### Task 2: Remover cópias e ligar o harness ao contrato

**Files:**

- Modify: `docs/architecture/testes-e-qualidade.md:5-26`
- Modify: `docs/harness/CODEX_OPERATING_MODEL.md:9-15`
- Modify: `docs/harness/CHANGE_PROTOCOL.md:3-9`
- Modify: `docs/harness/REVIEW_CHECKLIST.md:32-37`
- Modify: `docs/harness/TASK_BRIEF_TEMPLATE.md:38-43`
- Test: nenhum arquivo novo; usar as verificações read-only desta task

**Interfaces:**

- Consumes: contrato produzido pela Task 1
- Produces: documentos sem cópia da ordem de leitura ou da composição do
  alias

- [ ] **Step 1: Provar que as cópias ainda existem**

Run:

```bash
rg -n '^(compile --warnings-as-errors|format --check-formatted|credo --strict|test|dialyzer)$' \
  docs/architecture/testes-e-qualidade.md
rg -n '^1\. `AGENTS\.md`\.$' docs/harness/CODEX_OPERATING_MODEL.md
```

Expected: o primeiro comando encontra cinco linhas e o segundo encontra uma.

- [ ] **Step 2: Substituir a lista do documento de arquitetura por uma referência**

Substituir `Quality gate canônico`, incluindo o bloco de migrations, por:

```markdown
## Quality gate canônico

O gate agregado é `mix quality`. Sua composição atual, os comandos adicionais
para migrations e o momento de execução estão em
`docs/implementation/quality-gates.md`.

Este documento mantém a estratégia e a cobertura de testes. Ele não replica a
lista interna do alias.
```

- [ ] **Step 3: Remover a segunda ordem de leitura do operating model**

Substituir a lista numerada de `Leitura antes de agir` por:

```markdown
Siga integralmente a seção `Leitura obrigatória antes de trabalhar` de
`AGENTS.md`. Ela é a ordem canônica e inclui checkpoint, documentos relevantes,
ADRs, código e testes. Este operating model não mantém uma segunda lista.
```

- [ ] **Step 4: Adicionar links operacionais sem copiar comandos**

Em `CHANGE_PROTOCOL.md`, substituir o item final de `Mudança de código sem
alteração arquitetural` por:

```markdown
5. executar `mix quality` conforme
   `docs/implementation/quality-gates.md` antes do commit.
```

Em `REVIEW_CHECKLIST.md`, substituir o item `mix quality` por:

```markdown
- [ ] `mix quality` passa conforme
  `docs/implementation/quality-gates.md`.
```

Em `TASK_BRIEF_TEMPLATE.md`, substituir o item `quality gates` por:

```markdown
- `mix quality` conforme `docs/implementation/quality-gates.md`;
```

- [ ] **Step 5: Verificar as referências canônicas**

Run:

```bash
test -z "$(rg -n '^(compile --warnings-as-errors|format --check-formatted|credo --strict|test|dialyzer)$' docs/architecture/testes-e-qualidade.md)"
test -z "$(rg -n '^[1-9]\. `[^`]+`\.$' docs/harness/CODEX_OPERATING_MODEL.md)"
test "$(rg -l 'docs/implementation/quality-gates\.md' \
  docs/harness/CHANGE_PROTOCOL.md \
  docs/harness/REVIEW_CHECKLIST.md \
  docs/harness/TASK_BRIEF_TEMPLATE.md | wc -l)" -eq 3
git diff --check -- docs/architecture/testes-e-qualidade.md \
  docs/harness/CODEX_OPERATING_MODEL.md \
  docs/harness/CHANGE_PROTOCOL.md \
  docs/harness/REVIEW_CHECKLIST.md \
  docs/harness/TASK_BRIEF_TEMPLATE.md
mix quality
```

Expected: os três `test` saem com status 0, `git diff --check` não encontra
whitespace errors e `mix quality` termina com status 0 e nenhuma falha.

- [ ] **Step 6: Commitar as referências canônicas**

```bash
test -z "$(git diff --cached --name-only)"
git add docs/architecture/testes-e-qualidade.md \
  docs/harness/CODEX_OPERATING_MODEL.md \
  docs/harness/CHANGE_PROTOCOL.md \
  docs/harness/REVIEW_CHECKLIST.md \
  docs/harness/TASK_BRIEF_TEMPLATE.md
test "$(git diff --cached --name-only | wc -l)" -eq 5
git diff --cached --check
git commit -m "docs: point harness at canonical quality gates"
```

### Task 3: Fechar o incremento alternativo H0

**Files:**

- Modify: `docs/harness/specifications/H0-quality-contract.md:1-118`
- Modify: `docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md:85-106`
- Test: nenhum arquivo novo; usar as verificações read-only desta task

**Interfaces:**

- Consumes: contrato e referências materializados nas Tasks 1 e 2
- Produces: estado final de H0 dentro da trilha alternativa

- [ ] **Step 1: Atualizar o estado e a evidência da specification**

Substituir o status inicial por:

```markdown
> **Status: MATERIALIZADO NA TRILHA ALTERNATIVA.** Este contrato não altera a
> próxima tarefa de produto em `CURRENT.md`.
```

Adicionar antes de `Fora de escopo`:

```markdown
## Evidência materializada

- `docs/implementation/quality-gates.md`;
- `docs/decisions/ADR-0015-harness-multi-agente.md`;
- `docs/architecture/testes-e-qualidade.md`;
- `docs/harness/CODEX_OPERATING_MODEL.md`;
- `docs/harness/CHANGE_PROTOCOL.md`;
- `docs/harness/REVIEW_CHECKLIST.md`;
- `docs/harness/TASK_BRIEF_TEMPLATE.md`.
```

- [ ] **Step 2: Marcar H0 no roadmap sem promover a trilha para `CURRENT.md`**

Alterar o heading para:

```markdown
### H0. Consolidar o contrato de qualidade, materializado
```

Depois da linha da specification, adicionar:

```markdown
Plan: `docs/harness/plans/2026-08-30-h0-quality-contract.md`.
```

- [ ] **Step 3: Verificar o fechamento de H0**

Run:

```bash
rg -n '^> \*\*Status: MATERIALIZADO NA TRILHA ALTERNATIVA\.\*\*' \
  docs/harness/specifications/H0-quality-contract.md
rg -n '^### H0\. Consolidar o contrato de qualidade, materializado$' \
  docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md
git diff --check -- docs/harness/specifications/H0-quality-contract.md \
  docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md
git status --short
mix quality
```

Expected: cada `rg` encontra uma linha. A inspeção confirma que esta task
alterou somente os dois arquivos de H0, mesmo que mudanças preexistentes
continuem visíveis. `git diff --check` sai com status 0 e `mix quality` termina
com status 0, sem falhas, issues do Credo ou erros e skips do Dialyzer.

- [ ] **Step 4: Commitar o fechamento de H0**

```bash
test -z "$(git diff --cached --name-only)"
git add docs/harness/specifications/H0-quality-contract.md \
  docs/harness/QUALITY_ENFORCEMENT_ROADMAP.md
test "$(git diff --cached --name-only | wc -l)" -eq 2
git diff --cached --check
git commit -m "docs: mark H0 quality contract materialized"
```
