import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import kb_lint


class KnowledgeLintTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.kb = Path(self.tempdir.name) / "docs" / "knowledge"
        self.kb.mkdir(parents=True)

        self.write("README.md", self.document("schema", "# Schema\n"))
        self.write("INDEX.md", self.document("router", "# Index\n"))
        self.write("syntheses.md", self.document("syntheses", "# Syntheses\n"))
        self.write("gotchas.md", self.document("gotchas", "# Gotchas\n"))
        self.write("pins.md", self.document("pins", "# Pins\n"))
        self.write("log.md", self.document("log", "# Log\n"))
        self.write("proposals/README.md", self.document("proposals", "# Proposals\n"))
        self.write("raw/README.md", "# Immutable human source\n")

    def tearDown(self):
        self.tempdir.cleanup()

    def write(self, relative_path, content):
        path = self.kb / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def document(self, type_name, body):
        return f"---\ntype: {type_name}\nupdated: 2026-08-29\n---\n{body}"

    def findings(self):
        return kb_lint.lint(self.kb)

    def messages(self):
        return [finding.message for finding in self.findings()]

    def test_valid_empty_knowledge_base_has_no_findings(self):
        self.assertEqual([], self.findings())

    def test_reports_each_missing_required_file(self):
        (self.kb / "pins.md").unlink()
        (self.kb / "raw" / "README.md").unlink()

        self.assertEqual(
            [
                "required file missing",
                "required file missing",
            ],
            self.messages(),
        )
        self.assertEqual(
            ["pins.md", "raw/README.md"],
            [finding.path for finding in self.findings()],
        )

    def test_active_document_requires_frontmatter(self):
        self.write("syntheses.md", "# Syntheses\n")

        self.assertIn("missing frontmatter", self.messages())

    def test_active_document_requires_supported_type_and_updated(self):
        self.write("syntheses.md", "---\ntype: unsupported\n---\n# Syntheses\n")

        self.assertIn("unsupported frontmatter type", self.messages())
        self.assertNotIn("frontmatter missing updated", self.messages())

        self.write("syntheses.md", "---\ntype: syntheses\n---\n# Syntheses\n")

        self.assertIn("frontmatter missing updated", self.messages())

    def test_required_collection_requires_its_mapped_frontmatter_type(self):
        self.write("syntheses.md", self.document("gotchas", "# Syntheses\n"))

        self.assertIn("frontmatter type must be syntheses", self.messages())

    def test_raw_readme_is_exempt_from_active_content_checks(self):
        self.write("raw/README.md", "[[SYN-missing-reference]] <placeholder>\n")

        self.assertEqual([], self.findings())

    def test_invalid_semantic_id_is_an_error(self):
        self.write("syntheses.md", self.document("syntheses", "## SYN-runtime\n"))

        self.assertIn("invalid ID SYN-runtime", self.messages())

    def test_duplicate_semantic_id_is_an_error(self):
        entry = self.valid_synthesis("SYN-runtime-run-recovery")
        self.write("syntheses.md", self.document("syntheses", entry + entry))

        self.assertIn("duplicate ID SYN-runtime-run-recovery", self.messages())

    def test_active_collection_rejects_a_different_entry_prefix(self):
        self.write(
            "syntheses.md",
            self.document("syntheses", self.valid_gotcha("G-integrations-lock-order")),
        )

        self.assertIn("syntheses.md only accepts SYN- entries", self.messages())

    def test_dangling_reference_is_an_error(self):
        body = self.valid_synthesis("SYN-runtime-run-recovery")
        body += "- References: [[G-runtime-missing-snapshot]]\n"
        self.write("syntheses.md", self.document("syntheses", body))

        self.assertIn("dangling reference [[G-runtime-missing-snapshot]]", self.messages())

    def test_references_inside_fenced_and_inline_code_are_ignored(self):
        body = self.valid_synthesis("SYN-runtime-run-recovery")
        body += "```text\n[[G-runtime-code-only]]\n```\n"
        body += "`[[PIN-runtime-code-only]]`\n"
        self.write("syntheses.md", self.document("syntheses", body))

        self.assertEqual([], self.findings())

    def test_inline_code_value_is_not_empty(self):
        self.write(
            "syntheses.md",
            self.document("syntheses", self.valid_synthesis("SYN-runtime-run-recovery")),
        )

        self.assertEqual([], self.findings())

    def test_valid_persisted_proposal_is_not_an_active_definition(self):
        entry_id = "G-integrations-capture-format"
        self.write_proposal(
            entry_id,
            "docs/knowledge/gotchas.md",
            self.valid_gotcha(entry_id),
        )

        self.assertEqual([], self.findings())

    def test_active_reference_to_proposal_only_definition_is_dangling(self):
        entry_id = "G-integrations-capture-format"
        self.write_proposal(
            entry_id,
            "docs/knowledge/gotchas.md",
            self.valid_gotcha(entry_id),
        )
        body = self.valid_synthesis("SYN-runtime-run-recovery")
        body += f"- Related: [[{entry_id}]]\n"
        self.write("syntheses.md", self.document("syntheses", body))

        self.assertEqual(
            [
                kb_lint.Finding(
                    "ERROR",
                    "syntheses.md",
                    f"dangling reference [[{entry_id}]]",
                )
            ],
            self.findings(),
        )

    def test_proposal_requires_matching_filename(self):
        entry_id = "G-integrations-capture-format"
        self.write_proposal(
            entry_id,
            "docs/knowledge/gotchas.md",
            self.valid_gotcha(entry_id),
            filename="G-other-name.md",
        )

        self.assertIn(
            f"proposal filename must be {entry_id}.md", self.messages()
        )

    def test_proposal_requires_proposal_frontmatter_type(self):
        entry_id = "G-integrations-capture-format"
        self.write(
            f"proposals/{entry_id}.md",
            self.proposal(
                entry_id,
                "docs/knowledge/gotchas.md",
                self.valid_gotcha(entry_id),
                type_name="gotchas",
            ),
        )

        self.assertIn("proposal frontmatter type must be proposal", self.messages())

    def test_proposal_rejects_extra_frontmatter_fields(self):
        entry_id = "G-integrations-capture-format"
        proposal = self.proposal(
            entry_id,
            "docs/knowledge/gotchas.md",
            self.valid_gotcha(entry_id),
        ).replace("updated: 2026-08-29", "updated: 2026-08-29\nstatus: draft")
        self.write(f"proposals/{entry_id}.md", proposal)

        self.assertIn("proposal frontmatter fields are invalid", self.messages())

    def test_proposal_requires_an_active_collection_target(self):
        entry_id = "G-integrations-capture-format"
        self.write_proposal(
            entry_id,
            "docs/knowledge/INDEX.md",
            self.valid_gotcha(entry_id),
        )

        self.assertIn(
            "proposal target must be an active collection path", self.messages()
        )

    def test_proposal_prefix_must_match_its_target(self):
        entry_id = "G-integrations-capture-format"
        self.write_proposal(
            entry_id,
            "docs/knowledge/syntheses.md",
            self.valid_synthesis(entry_id),
        )

        self.assertIn("proposal entry_id prefix does not match target", self.messages())

    def test_proposal_candidate_must_match_its_entry_id(self):
        entry_id = "G-integrations-capture-format"
        self.write_proposal(
            entry_id,
            "docs/knowledge/gotchas.md",
            self.valid_gotcha("G-integrations-other-candidate"),
        )

        self.assertIn("proposal candidate ID must match entry_id", self.messages())

    def test_unexpected_non_raw_markdown_file_is_rejected(self):
        self.write("notes.md", self.document("schema", "# Notes\n"))

        self.assertIn("unexpected Markdown file", self.messages())

    def test_nested_proposal_file_is_rejected(self):
        entry_id = "G-integrations-capture-format"
        self.write(
            f"proposals/nested/{entry_id}.md",
            self.proposal(
                entry_id,
                "docs/knowledge/gotchas.md",
                self.valid_gotcha(entry_id),
            ),
        )

        self.assertIn("unexpected Markdown file", self.messages())

    def test_synthesis_requires_all_fields(self):
        self.write(
            "syntheses.md",
            self.document("syntheses", "## SYN-runtime-run-recovery\n"),
        )

        self.assertIn(
            "SYN-runtime-run-recovery missing fields: Autoridade, Contexto, Estado, Evidência, Síntese",
            self.messages(),
        )

    def test_synthesis_rejects_empty_required_field_value(self):
        entry = self.valid_synthesis("SYN-runtime-run-recovery").replace(
            "- Autoridade: `docs/decisions/ADR-0011-run-ownership-fencing.md`",
            "- Autoridade:   ",
        )
        self.write("syntheses.md", self.document("syntheses", entry))

        self.assertIn(
            "SYN-runtime-run-recovery empty fields: Autoridade", self.messages()
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

    def test_gotcha_rejects_empty_required_field_value(self):
        entry = self.valid_gotcha("G-integrations-lock-order").replace(
            "- Risco: A hybrid read can observe inconsistent authorities.",
            "- Risco:   ",
        )
        self.write("gotchas.md", self.document("gotchas", entry))

        self.assertIn(
            "G-integrations-lock-order empty fields: Risco", self.messages()
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

    def test_pin_rejects_empty_required_field_value(self):
        entry = self.valid_pin("PIN-snapshot-authority").replace(
            "- Escopo: Executions and Catalog.", "- Escopo:   "
        )
        self.write("pins.md", self.document("pins", entry))

        self.assertIn(
            "PIN-snapshot-authority empty fields: Escopo", self.messages()
        )

    def test_placeholder_in_active_file_is_an_error(self):
        self.write(
            "syntheses.md",
            self.document("syntheses", "# Syntheses\nproject: <slug>\n"),
        )

        self.assertIn("placeholder left in active content", self.messages())

    def test_200_newline_terminated_lines_are_not_a_warning(self):
        body = "line\n" * 196
        self.write("syntheses.md", self.document("syntheses", body))

        self.assertEqual([], self.findings())

    def test_201_newline_terminated_lines_are_a_warning(self):
        body = "line\n" * 197
        self.write("syntheses.md", self.document("syntheses", body))

        self.assertIn("201 lines exceeds 200", self.messages())

    def test_lint_is_deterministic_and_does_not_retain_findings(self):
        self.write("syntheses.md", "# Syntheses\n")
        first = self.findings()

        self.write("syntheses.md", self.document("syntheses", "# Syntheses\n"))

        self.assertEqual([], self.findings())
        self.assertEqual(
            [kb_lint.Finding("ERROR", "syntheses.md", "missing frontmatter")],
            first,
        )

    def test_strict_exit_code_ignores_info_and_reports_errors_or_warnings(self):
        info = [kb_lint.Finding("INFO", "INDEX.md", "orphan")]
        warning = [kb_lint.Finding("WARN", "INDEX.md", "large file")]
        error = [kb_lint.Finding("ERROR", "INDEX.md", "missing file")]

        self.assertEqual(0, kb_lint.strict_exit_code(info))
        self.assertEqual(1, kb_lint.strict_exit_code(warning))
        self.assertEqual(1, kb_lint.strict_exit_code(error))

    def test_main_uses_default_knowledge_path(self):
        self.assertEqual(Path("docs/knowledge"), kb_lint.DEFAULT_KB)

        original_cwd = Path.cwd()
        with redirect_stdout(io.StringIO()):
            try:
                os.chdir(self.tempdir.name)
                self.assertEqual(0, kb_lint.main([]))
            finally:
                os.chdir(original_cwd)

    def test_main_returns_strict_exit_code_for_explicit_knowledge_path(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(0, kb_lint.main(["--kb", str(self.kb), "--strict"]))
        self.write("syntheses.md", "# Syntheses\n")
        with redirect_stdout(io.StringIO()):
            self.assertEqual(1, kb_lint.main(["--kb", str(self.kb), "--strict"]))

    def valid_synthesis(self, entry_id):
        return (
            f"## {entry_id}\n"
            "- Contexto: Executions\n"
            "- Síntese: RunRecovery recovers durable ownership.\n"
            "- Autoridade: `docs/decisions/ADR-0011-run-ownership-fencing.md`\n"
            "- Evidência: `apps/leafcutter_runtime/test/leafcutter_runtime/run_recovery_test.exs`\n"
            "- Estado: derivado\n"
        )

    def valid_gotcha(self, entry_id):
        return (
            f"## {entry_id}\n"
            "- Contexto: Integrations\n"
            "- Situação: A deployment replacement is concurrent with resolution.\n"
            "- Risco: A hybrid read can observe inconsistent authorities.\n"
            "- Conduta: Follow the ratified lock order.\n"
            "- Evidência: `docs/decisions/ADR-0018-upstream-authorities-environment-deployment-resolution.md`\n"
            "- Estado: confirmado\n"
        )

    def valid_pin(self, entry_id):
        return (
            f"## {entry_id}\n"
            "- Intenção: Preserve snapshot authority boundaries.\n"
            "- Escopo: Executions and Catalog.\n"
            "- Autoridade relacionada: `docs/specifications/run-snapshot-v1.md`\n"
            "- Estado: ativo\n"
        )

    def proposal(self, entry_id, target, candidate, type_name="proposal"):
        return (
            f"---\ntype: {type_name}\nentry_id: {entry_id}\ntarget: {target}\n"
            "updated: 2026-08-29\n---\n"
            f"```markdown\n{candidate}```\n"
        )

    def write_proposal(self, entry_id, target, candidate, filename=None):
        self.write(
            f"proposals/{filename or f'{entry_id}.md'}",
            self.proposal(entry_id, target, candidate),
        )


if __name__ == "__main__":
    unittest.main()
