#!/usr/bin/env python3
"""Report deterministic, read-only health findings for the knowledge base."""

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
ENTRY_ID = re.compile(r"^(?:SYN|G|PIN)-[a-z0-9]+(?:-[a-z0-9]+)+$")
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
FINDING_ORDER = {"ERROR": 0, "WARN": 1, "INFO": 2}


@dataclass(frozen=True)
class Finding:
    """A deterministic lint result for one knowledge-base path."""

    level: str
    path: str
    message: str


def parse_frontmatter(text: str) -> dict[str, str] | None:
    """Parse the flat frontmatter subset required by knowledge-base documents."""
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
    """Yield semantic entry IDs and their content blocks in document order."""
    matches = list(ENTRY_HEADING.finditer(text))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        yield match.group(1), text[match.end() : end]


def fields_in(block: str) -> set[str]:
    """Return the labeled list fields declared in an entry block."""
    return {
        match.group(1)
        for match in re.finditer(r"^- ([^:\n]+):", block, re.MULTILINE)
    }


def active_markdown_files(kb: Path) -> list[Path]:
    """Return active Markdown files, excluding immutable human sources."""
    return [
        path
        for path in sorted(kb.rglob("*.md"))
        if "raw" not in path.relative_to(kb).parts
    ]


def lint(kb: Path) -> list[Finding]:
    """Return deterministic report-only findings for a knowledge-base directory."""
    findings = []
    definitions = {}
    references = []

    for relative_path in sorted(REQUIRED_FILES):
        if not (kb / relative_path).is_file():
            findings.append(Finding("ERROR", relative_path, "required file missing"))

    for path in active_markdown_files(kb):
        relative_path = str(path.relative_to(kb))
        text = path.read_text(encoding="utf-8")
        frontmatter = parse_frontmatter(text)

        if frontmatter is None:
            findings.append(Finding("ERROR", relative_path, "missing frontmatter"))
        elif frontmatter.get("type") not in SUPPORTED_TYPES:
            findings.append(
                Finding("ERROR", relative_path, "unsupported frontmatter type")
            )
        elif "updated" not in frontmatter:
            findings.append(
                Finding("ERROR", relative_path, "frontmatter missing updated")
            )

        if PLACEHOLDER.search(text):
            findings.append(
                Finding("ERROR", relative_path, "placeholder left in active content")
            )

        line_count = text.count("\n") + 1
        if line_count > MAX_LINES:
            findings.append(
                Finding(
                    "WARN",
                    relative_path,
                    f"{line_count} lines exceeds {MAX_LINES}",
                )
            )

        searchable = INLINE_CODE.sub("", FENCED_CODE.sub("", text))
        references.extend(
            (reference, relative_path) for reference in REFERENCE.findall(searchable)
        )

        for entry_id, block in entry_blocks(searchable):
            if not ENTRY_ID.fullmatch(entry_id):
                findings.append(Finding("ERROR", relative_path, f"invalid ID {entry_id}"))
                continue

            if entry_id in definitions:
                findings.append(
                    Finding("ERROR", relative_path, f"duplicate ID {entry_id}")
                )
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

    return sorted(
        findings,
        key=lambda item: (FINDING_ORDER[item.level], item.path, item.message),
    )


def strict_exit_code(findings: list[Finding]) -> int:
    """Return one when strict mode sees an error or warning, otherwise zero."""
    return int(any(item.level in {"ERROR", "WARN"} for item in findings))


def main(argv=None) -> int:
    """Run the report-only linter CLI and return its deterministic exit code."""
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
