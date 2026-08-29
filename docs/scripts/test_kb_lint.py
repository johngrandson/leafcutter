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


if __name__ == "__main__":
    unittest.main()
