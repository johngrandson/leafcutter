# Plano de implementação da base de conhecimento local

> **Para agentes executores:** SUB-SKILL OBRIGATÓRIO: use `superpowers:subagent-driven-development` ou `superpowers:executing-plans` para executar este plano tarefa por tarefa. Os passos usam checkboxes para acompanhamento.

**Objetivo:** Adotar uma base de conhecimento local, derivada e revisável, que ajude agentes e desenvolvedores a recuperar contexto do Leafcutter sem competir com código, testes, ADRs, specifications ou o checkpoint.

**Arquitetura:** O repositório continua sendo a autoridade. A base de conhecimento organiza fontes imutáveis, propostas produzidas por agentes e sínteses derivadas com provenance explícita. `AGENTS.md` contém o contrato compartilhado; `docs/knowledge/README.md` define o schema; os skills em `.claude/skills/` são adaptadores do Claude Code.

**Stack:** Markdown versionado, Git, Python 3 com biblioteca padrão para o linter, Claude Code project skills e o alias `mix quality` existente.

**Especificação:** `AGENTS.md`, `docs/decisions/ADR-0014-autoria-manual-e-harness.md`, `docs/decisions/ADR-0015-harness-multi-agente.md`, `docs/decisions/ADR-0016-documentacao-presente-e-futuro.md` e o desenho do LLM Wiki em `https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f`.

## Restrições globais

- A ordem de autoridade permanece: código e testes, ADRs e documentação arquitetural, contracts versionados, `CURRENT.md`, conhecimento derivado e conversa.
- A base atende a um único projeto Leafcutter. O roteamento usa contexts e capabilities existentes, não projetos fictícios.
- A base é derivada e não normativa. Uma divergência exige verificação na fonte canônica.
- Leitura, consulta e lint são operações sem escrita.
- Agentes só alteram conhecimento após pedido explícito ou aprovação de uma proposta concreta.
- `raw/` aceita somente fontes curadas por humanos e não muda depois da ingestão. Correções entram como nova fonte.
- Nenhum raw secret, credential, token, PII, payload de cliente ou documento sem permissão de versionamento entra na base.
- Documentação operacional e arquitetural permanece em pt-BR. Identificadores de código e nomes técnicos permanecem em inglês.
- O primeiro slice mantém Python apenas como ferramenta de desenvolvimento, sem pacote externo. Uma futura troca por Mix task exige necessidade observada.
- IDs são semânticos, por exemplo `SYN-runtime-run-recovery`, `G-integrations-deployment-lock-order` e `PIN-snapshot-authority`. Não existe contador global sujeito a corrida.
- O log registra apenas mutações da base. Consulta, calibração e lint sem mudança não geram commit nem entrada.
- Os arquivos Elixir modificados no worktree e `leafcutter-architecture-doc.pdf` estão fora deste plano. Cada commit deve preparar somente os paths da tarefa.

## Estrutura de arquivos alvo

```text
docs/knowledge/
├── README.md
├── INDEX.md
├── syntheses.md
├── gotchas.md
├── pins.md
├── log.md
├── proposals/
│   └── README.md
└── raw/
    └── README.md
```

Responsabilidades:

- `README.md` define autoridade, schema, segurança e operações.
- `INDEX.md` cataloga arquivos e roteia consultas por context.
- `syntheses.md` guarda conclusões derivadas com fontes canônicas.
- `gotchas.md` guarda armadilhas confirmadas e sua evidência.
- `pins.md` preserva a intenção de correções humanas durante reescritas, sem sobrepor autoridades.
- `proposals/` recebe material produzido por agentes antes de aprovação.
- `raw/` recebe fontes humanas imutáveis e permitidas para versionamento.
- `log.md` registra somente ingestão, captura aprovada e consolidação aplicada.

## Fora do escopo

- Popular a base com uma extração ampla do código existente.
- RAG, embeddings, BM25, qmd, Obsidian, banco vetorial ou MCP específico.
- Execução agendada de lint ou consolidação.
- Skills equivalentes para todas as ferramentas de agente.
- Arquivo por context antes de algum arquivo ativo ultrapassar 200 linhas.
- Mudanças na arquitetura de runtime, contexts, schemas Ecto ou contracts executáveis.

---

### Task 1: Ratificar a governança da base

**Arquivos:**

- Criar: `docs/decisions/ADR-0019-base-conhecimento-local.md`
- Modificar: `docs/decisions/README.md`

**Interfaces:**

- Consome: hierarquia de autoridade de `AGENTS.md` e contratos dos ADRs 0014, 0015 e 0016.
- Produz: decisão ratificada que autoriza as tarefas seguintes.

- [ ] **Passo 1: Criar o ADR como proposta**

O ADR deve registrar exatamente estas decisões:

```markdown
# ADR-0019: Base de conhecimento local derivada

- Status: Proposed
- Estado de implementação: NÃO MATERIALIZADO

## Contexto

O Leafcutter precisa acumular sínteses, gotchas e correções humanas sem
rederivar esse conhecimento em cada sessão. A nova camada não pode criar
uma fonte de autoridade paralela nem um contrato exclusivo de uma ferramenta.

## Decisão

A base em `docs/knowledge/` é derivada e não normativa. Cada claim ativo
referencia sua autoridade. `AGENTS.md` define o contrato compartilhado e
skills específicos apenas adaptam esse contrato a cada ferramenta.

Fontes humanas em `raw/` são imutáveis. Conteúdo produzido por agentes nasce
em `proposals/` e só entra na base ativa após aprovação. Consultas e lint não
alteram arquivos. Pins provocam reconciliação, nunca sobrepõem código, testes,
ADRs, specifications ou `CURRENT.md`.

## Consequências

- o desenvolvedor continua autor principal;
- conflitos retornam à fonte canônica;
- o roteamento segue contexts do Leafcutter;
- nenhuma infraestrutura de busca entra no primeiro slice;
- a base possui lint determinístico antes do merge.
```

- [ ] **Passo 2: Submeter a decisão à ratificação humana**

Apresentar o ADR completo. Parar se houver objeção à natureza derivada, à escrita aprovada ou à separação `raw/` e `proposals/`.

- [ ] **Passo 3: Marcar a decisão como aceita**

Somente após aprovação, alterar:

```text
Status: Accepted
Estado de implementação: NÃO MATERIALIZADO
```

- [ ] **Passo 4: Indexar o ADR**

Adicionar em `docs/decisions/README.md`:

```markdown
| ADR-0019 | Base de conhecimento local derivada | NÃO MATERIALIZADO |
```

- [ ] **Passo 5: Verificar a decisão**

Executar:

```bash
rg -n "ADR-0019|base de conhecimento local|derivada|não normativa" \
  docs/decisions/ADR-0019-base-conhecimento-local.md \
  docs/decisions/README.md
```

Esperado: o ADR está `Accepted`, o estado está `NÃO MATERIALIZADO` e o índice possui uma única entrada.

- [ ] **Passo 6: Commit**

```bash
git add docs/decisions/ADR-0019-base-conhecimento-local.md docs/decisions/README.md
git commit -m "docs: ratify local knowledge base governance"
```

---

### Task 2: Materializar o schema e a estrutura mínima

**Arquivos:**

- Criar: `docs/knowledge/README.md`
- Criar: `docs/knowledge/syntheses.md`
- Criar: `docs/knowledge/proposals/README.md`
- Modificar: `docs/knowledge/INDEX.md`
- Modificar: `docs/knowledge/gotchas.md`
- Modificar: `docs/knowledge/pins.md`
- Modificar: `docs/knowledge/log.md`
- Modificar: `docs/knowledge/raw/README.md`
- Remover: `docs/knowledge/business-rules.md`
- Remover: `docs/knowledge/conventions.md`
- Remover: `docs/knowledge/archive/gotchas-archive.md`
- Modificar: `docs/README.md`

**Interfaces:**

- Consome: ADR-0019 aceito.
- Produz: schema compartilhado e base vazia, sem facts fictícios.

- [ ] **Passo 1: Registrar a falha do seed atual**

Executar:

```bash
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
```

Esperado: exit 1, três referências pendentes e três warnings de placeholders.

- [ ] **Passo 2: Criar o schema compartilhado**

`docs/knowledge/README.md` deve possuir frontmatter `type: schema`, a ordem de autoridade completa e estas seções:

```text
Propósito
Autoridade e conflitos
Camadas
Tipos de entrada
Provenance
Operações de consulta, ingestão, captura e lint
Política de escrita e revisão
Segurança e privacidade
Critérios para dividir arquivos
```

Definir os formatos ativos:

```markdown
## SYN-runtime-run-recovery
- Contexto: Executions
- Síntese: RunRecovery recupera ownership durável; Registry permanece local.
- Autoridade: `docs/decisions/ADR-0011-run-ownership-fencing.md`
- Evidência: `apps/leafcutter_runtime/test/leafcutter_runtime/run_recovery_test.exs`
- Estado: derivado

## G-integrations-deployment-lock-order
- Contexto: Integrations
- Situação: resolução concorrente com replace de deployment.
- Risco: leitura híbrida das authorities mutáveis.
- Conduta: respeitar a ordem de locks ratificada no ADR-0018.
- Evidência: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`
- Estado: confirmado

## PIN-snapshot-authority
- Intenção: RunSnapshot não cria authority paralela para PackageVersion.
- Escopo: Executions e Catalog.
- Autoridade relacionada: `docs/specifications/run-snapshot-v1.md`
- Estado: ativo
```

Os exemplos ficam apenas no schema. Eles não entram nos arquivos ativos.

- [ ] **Passo 3: Reescrever o índice para um projeto único**

`INDEX.md` deve listar os contexts ratificados e apontar para as fontes canônicas antes dos arquivos derivados:

```text
Organizations
Catalog
Connections
Integrations
Executions e runtime
Notifications
Audit
```

O roteamento deve carregar somente `syntheses.md`, `gotchas.md` ou `pins.md` quando o resumo do índice indicar relevância. `raw/`, `proposals/` e `log.md` não participam de consultas normais.

- [ ] **Passo 4: Limpar os arquivos ativos**

Criar ou reescrever `syntheses.md`, `gotchas.md` e `pins.md` com frontmatter válido, explicação curta e a frase `Nenhuma entrada registrada.`. Remover todos os exemplos de pedidos, cupons, timezone, TypeScript e o pin `PIN-000`.

- [ ] **Passo 5: Separar propostas e fontes**

`proposals/README.md` deve declarar que agentes podem criar candidatos somente após pedido explícito. `raw/README.md` deve declarar que humanos adicionam fontes, agentes apenas leem e correções entram como novos arquivos.

- [ ] **Passo 6: Reduzir o log a mutações**

`log.md` deve permanecer sem entradas históricas inventadas e documentar estes eventos permitidos:

```text
ingestão de fonte
captura aprovada
promoção aprovada
consolidação aplicada
```

- [ ] **Passo 7: Integrar a área ao índice de documentação**

Adicionar em `docs/README.md` uma seção `Base de conhecimento` que a classifique como `DERIVADA` e aponte para `knowledge/README.md` e `knowledge/INDEX.md`.

- [ ] **Passo 8: Verificar a estrutura**

Executar:

```bash
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
rg -n "N independent|knowledge/projects|knowledge/global|Cancel order|Discount calculation|OrderEvents|PIN-000" docs/knowledge
```

Esperado: linter com exit 0 e `rg` sem resultados.

- [ ] **Passo 9: Commit**

```bash
git add -A -- docs/knowledge docs/README.md
git commit -m "docs: establish local knowledge base schema"
```

---

### Task 3: Integrar o contrato compartilhado dos agentes

**Arquivos:**

- Modificar: `AGENTS.md`
- Modificar: `docs/harness/README.md`
- Remover: `docs/CLAUDE.md`

**Interfaces:**

- Consome: `docs/knowledge/README.md` e ADR-0019.
- Produz: uma regra compartilhada por Codex, Claude Code e outros agentes.

- [ ] **Passo 1: Adicionar a regra compartilhada em `AGENTS.md`**

Adicionar após a leitura obrigatória:

```markdown
## Base de conhecimento local

Depois da leitura canônica, consulte `docs/knowledge/INDEX.md` quando a tarefa
envolver semântica de domínio, ambiguidade conhecida, correção humana ou uma
decisão que possa ter sido sintetizada anteriormente.

A base é derivada e não normativa. Em conflito, volte à ordem de autoridade
deste arquivo. Consulta e lint não alteram a base. Escritas exigem pedido
explícito ou aprovação de uma proposta concreta.
```

- [ ] **Passo 2: Remover a instrução exclusiva e tardia**

Remover `docs/CLAUDE.md`. O `CLAUDE.md` da raiz continua importando `AGENTS.md`; nenhuma instrução nova deve ser duplicada ali.

- [ ] **Passo 3: Documentar a integração no harness**

Adicionar em `docs/harness/README.md` que a base guarda conhecimento derivado, enquanto `AGENTS.md`, `CURRENT.md` e o operating model continuam sendo o contrato dos agentes.

- [ ] **Passo 4: Verificar precedência e paths**

Executar:

```bash
rg -n "Base de conhecimento local|derivada e não normativa|docs/knowledge/INDEX.md" \
  AGENTS.md docs/harness/README.md
test ! -e docs/CLAUDE.md
```

Esperado: as regras aparecem no contrato compartilhado e `docs/CLAUDE.md` não existe.

- [ ] **Passo 5: Commit**

```bash
git add -A -- AGENTS.md docs/harness/README.md docs/CLAUDE.md
git commit -m "docs: share knowledge base rules across agents"
```

---

### Task 4: Reduzir os skills ao primeiro slice operacional

**Arquivos:**

- Modificar: `.claude/skills/calibrate-task/SKILL.md`
- Modificar: `.claude/skills/capture-gotcha/SKILL.md`
- Modificar: `.claude/skills/kb-lint/SKILL.md`
- Remover: `.claude/skills/extract-rules/SKILL.md`
- Remover: `.claude/skills/consolidate-kb/SKILL.md`

**Interfaces:**

- Consome: contrato de `AGENTS.md` e schema de `docs/knowledge/README.md`.
- Produz: consulta sem escrita, captura aprovada e lint report-only para Claude Code.

- [ ] **Passo 1: Restringir `calibrate-task`**

O frontmatter deve acionar o skill somente para planejamento de domínio, ambiguidade semântica, correções conhecidas e decisões arquiteturais. Excluir commit, push, formatter, execução de testes e verificação mecânica.

O corpo deve executar:

```text
1. confirmar que AGENTS, CURRENT e documentos canônicos relevantes já foram lidos;
2. abrir docs/knowledge/INDEX.md;
3. carregar somente arquivos derivados relevantes;
4. confrontar cada claim com sua autoridade;
5. reportar conhecimento coberto e ambiguidades restantes;
6. não alterar log ou qualquer arquivo.
```

- [ ] **Passo 2: Tornar `capture-gotcha` explicitamente mutável**

Adicionar ao frontmatter:

```yaml
disable-model-invocation: true
```

O skill deve primeiro produzir o texto completo da entrada proposta. Somente depois da aprovação do desenvolvedor ele altera `docs/knowledge/gotchas.md`, `pins.md`, `syntheses.md`, `INDEX.md` e `log.md` conforme necessário.

Remover contador de ocorrências. Promoção depende de evidência canônica e aprovação, não de um número arbitrário.

- [ ] **Passo 3: Corrigir `kb-lint`**

O comando documentado deve ser:

```bash
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
```

O skill interpreta o relatório e não altera arquivos nem `log.md`.

- [ ] **Passo 4: Adiar workflows sem demanda**

Remover `extract-rules` e `consolidate-kb` do primeiro slice. Registrar em `docs/knowledge/README.md` que eles podem voltar quando houver uma extração explicitamente solicitada ou arquivos ativos acima de 200 linhas.

- [ ] **Passo 5: Verificar os skills**

Executar:

```bash
rg -n "knowledge/|scripts/kb_lint|knowledge/projects|knowledge/global|Occurrences|weekly|ALWAYS" .claude/skills
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
```

Esperado: nenhum path sem prefixo `docs/`, nenhuma topologia multi-projeto, nenhum contador e linter com exit 0. A palavra `ALWAYS` não deve ampliar os gatilhos para toda tarefa.

- [ ] **Passo 6: Commit**

```bash
git add -A -- .claude/skills docs/knowledge/README.md
git commit -m "chore: scope knowledge base skills"
```

---

### Task 5: Tornar o linter testável e alinhado ao schema

**Arquivos:**

- Modificar: `docs/scripts/kb_lint.py`
- Criar: `docs/scripts/test_kb_lint.py`

**Interfaces:**

- Consome: tipos de entrada definidos em `docs/knowledge/README.md`.
- Produz: `lint(kb: Path) -> list[Finding]` e CLI com exit determinístico.

- [ ] **Passo 1: Escrever testes que falham para o contrato novo**

Usar `unittest` e `tempfile.TemporaryDirectory`. O arquivo de teste deve construir uma base isolada e cobrir o contrato completo:

```python
import tempfile
import unittest
from pathlib import Path

import kb_lint


class KnowledgeLintTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.kb = Path(self.tempdir.name) / "docs" / "knowledge"
        self.kb.mkdir(parents=True)
        (self.kb / "proposals").mkdir()
        (self.kb / "raw").mkdir()

        self.write("README.md", self.document("schema", "# Schema\n"))
        self.write("INDEX.md", self.document("router", "# Índice\n"))
        self.write("syntheses.md", self.document("syntheses", "# Sínteses\n"))
        self.write("gotchas.md", self.document("gotchas", "# Gotchas\n"))
        self.write("pins.md", self.document("pins", "# Pins\n"))
        self.write("log.md", self.document("log", "# Log\n"))
        self.write(
            "proposals/README.md",
            self.document("proposals", "# Propostas\n"),
        )
        self.write("raw/README.md", "# Fontes imutáveis\n")

    def tearDown(self):
        self.tempdir.cleanup()

    def write(self, relative_path, content):
        path = self.kb / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def document(self, type_name, body):
        return f"---\ntype: {type_name}\nupdated: 2026-08-29\n---\n{body}"

    def messages(self):
        return [finding.message for finding in kb_lint.lint(self.kb)]

    def test_valid_empty_knowledge_base_has_no_findings(self):
        self.assertEqual([], kb_lint.lint(self.kb))

    def test_placeholder_in_active_file_is_an_error(self):
        self.write(
            "syntheses.md",
            self.document("syntheses", "# Sínteses\nproject: <slug>\n"),
        )
        self.assertIn("placeholder left in active content", self.messages())

    def test_duplicate_semantic_id_is_an_error(self):
        entry = self.valid_synthesis("SYN-runtime-run-recovery")
        self.write("syntheses.md", self.document("syntheses", entry + entry))
        self.assertIn("duplicate ID SYN-runtime-run-recovery", self.messages())

    def test_dangling_reference_is_an_error(self):
        body = self.valid_synthesis("SYN-runtime-run-recovery")
        body += "- Referências: [[G-runtime-missing-snapshot]]\n"
        self.write("syntheses.md", self.document("syntheses", body))
        self.assertIn(
            "dangling reference [[G-runtime-missing-snapshot]]",
            self.messages(),
        )

    def test_references_inside_code_fences_are_ignored(self):
        body = self.valid_synthesis("SYN-runtime-run-recovery")
        body += "```text\n[[G-runtime-example-only]]\n```\n"
        self.write("syntheses.md", self.document("syntheses", body))
        self.assertEqual([], kb_lint.lint(self.kb))

    def test_synthesis_requires_all_fields(self):
        self.write(
            "syntheses.md",
            self.document("syntheses", "## SYN-runtime-run-recovery\n"),
        )
        self.assertIn(
            "SYN-runtime-run-recovery missing fields: Autoridade, Contexto, Estado, Evidência, Síntese",
            self.messages(),
        )

    def test_gotcha_requires_all_fields(self):
        self.write(
            "gotchas.md",
            self.document("gotchas", "## G-integrations-lock-order\n"),
        )
        self.assertIn(
            "G-integrations-lock-order missing fields: Conduta, Contexto, Estado, Evidência, Risco, Situação",
            self.messages(),
        )

    def test_pin_requires_all_fields(self):
        self.write(
            "pins.md",
            self.document("pins", "## PIN-snapshot-authority\n"),
        )
        self.assertIn(
            "PIN-snapshot-authority missing fields: Autoridade relacionada, Escopo, Estado, Intenção",
            self.messages(),
        )

    def test_strict_exit_code_ignores_info(self):
        info = [kb_lint.Finding("INFO", "INDEX.md", "orphan")]
        warning = [kb_lint.Finding("WARN", "INDEX.md", "large file")]
        self.assertEqual(0, kb_lint.strict_exit_code(info))
        self.assertEqual(1, kb_lint.strict_exit_code(warning))

    def test_default_cli_path_is_docs_knowledge(self):
        self.assertEqual(Path("docs/knowledge"), kb_lint.DEFAULT_KB)

    def valid_synthesis(self, entry_id):
        return (
            f"## {entry_id}\n"
            "- Contexto: Executions\n"
            "- Síntese: RunRecovery recupera ownership durável.\n"
            "- Autoridade: `docs/decisions/ADR-0011-run-ownership-fencing.md`\n"
            "- Evidência: `apps/leafcutter_runtime/test/leafcutter_runtime/run_recovery_test.exs`\n"
            "- Estado: derivado\n"
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Passo 2: Executar os testes e confirmar a falha**

```bash
python3 -m unittest discover -s docs/scripts -p 'test_*.py' -v
```

Esperado: falhas por ausência de `Finding`, `lint/2`, IDs semânticos, validação de fields e path default correto.

- [ ] **Passo 3: Refatorar o linter em funções puras**

Implementar sem dependências externas. O módulo deve usar estas constantes, tipos e funções como interface estável:

```python
import argparse
import re
from dataclasses import dataclass
from pathlib import Path

DEFAULT_KB = Path("docs/knowledge")
MAX_LINES = 200
REQUIRED_FILES = {
    "README.md",
    "INDEX.md",
    "syntheses.md",
    "gotchas.md",
    "pins.md",
    "log.md",
    "proposals/README.md",
    "raw/README.md",
}
SUPPORTED_TYPES = {
    "schema",
    "router",
    "syntheses",
    "gotchas",
    "pins",
    "log",
    "proposals",
}
ENTRY_ID = re.compile(
    r"^(?:SYN|G|PIN)-[a-z0-9]+(?:-[a-z0-9]+)+$"
)
ENTRY_HEADING = re.compile(r"^## ((?:SYN|G|PIN)-\S+)\s*$", re.MULTILINE)
REFERENCE = re.compile(r"\[\[((?:SYN|G|PIN)-[^\]]+)\]\]")
FENCED_CODE = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE = re.compile(r"`[^`\n]*`")
PLACEHOLDER = re.compile(r"<[^>]+>|\bXXX\b|example\s*[-:]", re.IGNORECASE)
REQUIRED_FIELDS = {
    "SYN": {"Contexto", "Síntese", "Autoridade", "Evidência", "Estado"},
    "G": {"Contexto", "Situação", "Risco", "Conduta", "Evidência", "Estado"},
    "PIN": {"Intenção", "Escopo", "Autoridade relacionada", "Estado"},
}


@dataclass(frozen=True)
class Finding:
    level: str
    path: str
    message: str


def parse_frontmatter(text: str) -> dict[str, str] | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    result = {}
    for line in text[4:end].splitlines():
        key, separator, value = line.partition(":")
        if separator and key and value.strip():
            result[key.strip()] = value.strip()
    return result


def entry_blocks(text: str):
    matches = list(ENTRY_HEADING.finditer(text))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        yield match.group(1), text[match.end():end]


def fields_in(block: str) -> set[str]:
    return {
        match.group(1)
        for match in re.finditer(r"^- ([^:\n]+):", block, re.MULTILINE)
    }


def lint(kb: Path) -> list[Finding]:
    findings = []
    definitions = {}
    references = []

    for relative_path in sorted(REQUIRED_FILES):
        if not (kb / relative_path).is_file():
            findings.append(Finding("ERROR", relative_path, "required file missing"))

    active_files = [
        path
        for path in sorted(kb.rglob("*.md"))
        if "raw" not in path.relative_to(kb).parts
    ]

    for path in active_files:
        relative_path = str(path.relative_to(kb))
        text = path.read_text(encoding="utf-8")
        frontmatter = parse_frontmatter(text)
        if frontmatter is None:
            findings.append(Finding("ERROR", relative_path, "missing frontmatter"))
        elif frontmatter.get("type") not in SUPPORTED_TYPES:
            findings.append(Finding("ERROR", relative_path, "unsupported frontmatter type"))
        elif "updated" not in frontmatter:
            findings.append(Finding("ERROR", relative_path, "frontmatter missing updated"))

        if PLACEHOLDER.search(text):
            findings.append(Finding("ERROR", relative_path, "placeholder left in active content"))

        line_count = text.count("\n") + 1
        if line_count > MAX_LINES:
            findings.append(Finding("WARN", relative_path, f"{line_count} lines exceeds {MAX_LINES}"))

        searchable = INLINE_CODE.sub("", FENCED_CODE.sub("", text))
        references.extend((reference, relative_path) for reference in REFERENCE.findall(searchable))

        for entry_id, block in entry_blocks(searchable):
            if not ENTRY_ID.fullmatch(entry_id):
                findings.append(Finding("ERROR", relative_path, f"invalid ID {entry_id}"))
                continue
            if entry_id in definitions:
                findings.append(Finding("ERROR", relative_path, f"duplicate ID {entry_id}"))
            else:
                definitions[entry_id] = relative_path

            prefix = entry_id.split("-", 1)[0]
            missing = sorted(REQUIRED_FIELDS[prefix] - fields_in(block))
            if missing:
                findings.append(
                    Finding(
                        "ERROR",
                        relative_path,
                        f"{entry_id} missing fields: {', '.join(missing)}",
                    )
                )

    for reference, relative_path in references:
        if reference not in definitions:
            findings.append(
                Finding("ERROR", relative_path, f"dangling reference [[{reference}]]")
            )

    order = {"ERROR": 0, "WARN": 1, "INFO": 2}
    return sorted(findings, key=lambda item: (order[item.level], item.path, item.message))


def strict_exit_code(findings: list[Finding]) -> int:
    return int(any(item.level in {"ERROR", "WARN"} for item in findings))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kb", type=Path, default=DEFAULT_KB)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args(argv)
    findings = lint(args.kb)
    for finding in findings:
        print(f"{finding.level:5} {finding.path}: {finding.message}")
    if args.strict:
        return strict_exit_code(findings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Substituir IDs sequenciais por:

```text
SYN-runtime-run-recovery
G-integrations-deployment-lock-order
PIN-snapshot-authority
```

No código real, as regexes devem aceitar exemplos concretos como `SYN-runtime-run-recovery`, sem manter os marcadores angulares.

- [ ] **Passo 4: Validar o que o linter realmente garante**

Manter somente checks determinísticos:

```text
frontmatter obrigatório e type conhecido
files obrigatórios presentes
IDs reconhecidos e únicos
refs existentes
fields obrigatórios por tipo
placeholders proibidos em arquivos ativos
code spans e fenced blocks ignorados na coleta de refs
limite de 200 linhas
```

Remover a promessa de detectar staleness por timestamps de Git. O primeiro slice não consegue provar freshness com segurança, sobretudo diante de arquivos untracked ou mudanças sem commit.

- [ ] **Passo 5: Executar testes e lint real**

```bash
python3 -m unittest discover -s docs/scripts -p 'test_*.py' -v
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
```

Esperado: todos os testes passam e o lint real termina com exit 0.

- [ ] **Passo 6: Commit**

```bash
git add docs/scripts/kb_lint.py docs/scripts/test_kb_lint.py
git commit -m "test: define knowledge lint contract"
```

---

### Task 6: Integrar a base ao gate de qualidade

**Arquivos:**

- Modificar: `mix.exs`
- Modificar: `docs/implementation/quality-gates.md`

**Interfaces:**

- Consome: linter e testes aprovados na Tarefa 5.
- Produz: `mix quality` falhando quando a estrutura documental estiver inválida.

- [ ] **Passo 1: Confirmar que o gate atual ignora a base**

Executar:

```bash
rg -n "kb_lint|knowledge" mix.exs docs/implementation/quality-gates.md
```

Esperado: nenhum comando de knowledge lint no alias atual.

- [ ] **Passo 2: Adicionar os dois comandos ao alias**

Inserir uma função antes da compilação. Não usar `mix cmd`, porque em uma umbrella ele muda para o diretório de cada child application e executaria os checks quatro vezes fora da raiz.

```elixir
quality: [
  &run_knowledge_quality/1,
  "compile --warnings-as-errors",
  "format --check-formatted",
  "credo --strict",
  "test",
  &run_dialyzer/1
]

defp run_knowledge_quality(_) do
  run_python!(
    "knowledge lint tests",
    ["-m", "unittest", "discover", "-s", "docs/scripts", "-p", "test_*.py"]
  )

  run_python!(
    "knowledge lint",
    ["docs/scripts/kb_lint.py", "--kb", "docs/knowledge", "--strict"]
  )
end

defp run_python!(label, args) do
  {output, status} =
    System.cmd("python3", args, stderr_to_stdout: true)

  IO.write(output)

  if status != 0 do
    Mix.raise("#{label} failed with exit status #{status}")
  end
end
```

- [ ] **Passo 3: Documentar o gate**

Atualizar `docs/implementation/quality-gates.md` com os testes do linter, o lint estrito e a exigência de Python 3 sem pacotes externos.

- [ ] **Passo 4: Executar o gate completo**

```bash
mix quality
```

Esperado: testes do linter, lint da base, compilação, formatter, Credo, ExUnit e Dialyzer passam.

- [ ] **Passo 5: Commit**

```bash
git add mix.exs docs/implementation/quality-gates.md
git commit -m "chore: include knowledge lint in quality gate"
```

---

### Task 7: Fechar o milestone documental

**Arquivos:**

- Modificar: `docs/decisions/ADR-0019-base-conhecimento-local.md`
- Modificar: `docs/decisions/README.md`
- Modificar: `docs/checkpoint/CURRENT.md`

**Interfaces:**

- Consome: estrutura, skills e gate aprovados nas tarefas anteriores.
- Produz: estado documental coerente e ponto de continuidade atualizado.

- [ ] **Passo 1: Atualizar o estado de materialização**

Alterar o ADR e seu índice para `MATERIALIZADO` sem reescrever o contexto ou as alternativas.

- [ ] **Passo 2: Atualizar o checkpoint sem mudar a próxima fronteira de produto**

Adicionar aos milestones concluídos:

```text
Local derived knowledge base governance
Local knowledge schema and Claude adapters
Knowledge lint in mix quality
```

Registrar que essa mudança pertence ao harness e não altera a próxima fronteira `Contracts/JSV + Connector/Operation/Transport`.

- [ ] **Passo 3: Rodar verificações finais**

```bash
python3 -m unittest discover -s docs/scripts -p 'test_*.py' -v
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
mix quality
git diff --check
git status --short
```

Esperado: todos os gates passam. `git status` pode exibir o worktree Elixir preexistente e a remoção do PDF, mas nenhum desses paths entra no commit desta tarefa.

- [ ] **Passo 4: Revisar contra o ADR**

Confirmar manualmente:

```text
nenhum claim fictício ativo
nenhuma regra exclusiva em docs/CLAUDE.md
nenhuma escrita automática em consulta ou lint
nenhum path knowledge/ ou scripts/ incorreto
nenhuma autoridade atribuída a pin ou síntese
nenhum raw secret ou dado privado
```

- [ ] **Passo 5: Commit**

```bash
git add \
  docs/decisions/ADR-0019-base-conhecimento-local.md \
  docs/decisions/README.md \
  docs/checkpoint/CURRENT.md
git commit -m "docs: complete local knowledge base milestone"
```

## Critérios de aceite do plano

- ADR-0019 aceito antes de qualquer mudança de comportamento dos agentes.
- Base local descrita como derivada em `AGENTS.md`, ADR e schema.
- Paths reais usam sempre `docs/knowledge/` e `docs/scripts/`.
- Nenhuma topologia de múltiplos projetos permanece.
- Arquivos ativos não contêm exemplos fictícios nem placeholders.
- Consulta e lint são read-only.
- Captura exige invocação e aprovação explícitas.
- `raw/` e `proposals/` possuem ownerships distintos.
- Linter possui testes determinísticos e faz parte do `mix quality`.
- `mix quality` e `git diff --check` passam.
- Commits não incluem mudanças Elixir ou PDF fora do escopo.

## Sequência futura, não autorizada por este plano

Quando houver pelo menos uma extração solicitada, planejar um skill explícito que escreva propostas. Quando um arquivo ativo ultrapassar 200 linhas ou surgirem duplicatas reais, planejar consolidação e divisão por context. Infraestrutura de busca só entra após medir falhas de recuperação com o `INDEX.md` atual.

## Correções após revisão ampla

Esta seção registra correções incrementais encontradas na revisão final, sem
reescrever os passos originais do plano. Elas preservam o objetivo da base de
conhecimento local derivada e não alteram o roadmap de produto.

- O diagrama de autoridade em `AGENTS.md` passou a incluir explicitamente a
  base de conhecimento derivada entre `CURRENT.md` e conversas/memória.
- A captura por agentes passou a persistir candidatos em `proposals/` antes da
  aprovação humana, mantendo a promoção para coleções ativas como ação
  posterior e explicitamente aprovada.
- O linter passou a rejeitar campos obrigatórios vazios, além de rótulos
  obrigatórios ausentes, para que provenance e demais claims possuam valor.
- O linter passou a vincular tipo e prefixo à coleção correta e a isolar
  propostas da resolução de referências ativas, preservando sua ausência de
  authority antes da promoção.
