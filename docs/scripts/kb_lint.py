#!/usr/bin/env python3
"""Report deterministic, read-only health findings for the knowledge base."""

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

DEFAULT_KB = Path("docs/knowledge")
MAX_LINES = 200
REQUIRED_COLLECTION_TYPES = {
    "README.md": "schema",
    "INDEX.md": "router",
    "syntheses.md": "syntheses",
    "gotchas.md": "gotchas",
    "pins.md": "pins",
    "log.md": "log",
    "proposals/README.md": "proposals",
}
REQUIRED_FILES = set(REQUIRED_COLLECTION_TYPES) | {"raw/README.md"}
SUPPORTED_TYPES = set(REQUIRED_COLLECTION_TYPES.values())
ACTIVE_COLLECTIONS = {
    "syntheses.md": ("SYN", "syntheses"),
    "gotchas.md": ("G", "gotchas"),
    "pins.md": ("PIN", "pins"),
}
PROPOSAL_FIELDS = {"type", "entry_id", "target", "updated"}
PROPOSAL_TARGETS = {
    f"docs/knowledge/{path}": prefix
    for path, (prefix, _) in ACTIVE_COLLECTIONS.items()
}
ENTRY_ID = re.compile(r"^(?:SYN|G|PIN)-[a-z0-9]+(?:-[a-z0-9]+)+$")
ENTRY_HEADING = re.compile(r"^## ((?:SYN|G|PIN)-\S+)\s*$", re.MULTILINE)
REFERENCE = re.compile(r"\[\[((?:SYN|G|PIN)-[^\]]+)\]\]")
FENCED_CODE = re.compile(r"```.*?```", re.DOTALL)
FENCED_MARKDOWN = re.compile(r"\A\s*```markdown\n(?P<candidate>.*?)```\s*\Z", re.DOTALL)
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
        if separator and key:
            result[key.strip()] = value.strip()
    return result


def frontmatter_body(text: str) -> str:
    """Return the document body after a valid frontmatter block."""
    end = text.find("\n---\n", 4)
    return text[end + 5 :] if end != -1 else ""


def entry_blocks(text: str):
    """Yield semantic entry IDs and their content blocks in document order."""
    matches = list(ENTRY_HEADING.finditer(text))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        yield match.group(1), text[match.end() : end]


def fields_in(block: str) -> dict[str, str]:
    """Return labeled list fields and their trimmed values from an entry block."""
    return {
        match.group(1): match.group(2).strip()
        for match in re.finditer(r"^- ([^:\n]+):(.*)$", block, re.MULTILINE)
    }


def active_markdown_files(kb: Path) -> list[Path]:
    """Return non-raw Markdown files in deterministic path order."""
    return [
        path
        for path in sorted(kb.rglob("*.md"))
        if "raw" not in path.relative_to(kb).parts
    ]


def is_dynamic_proposal(relative_path: str) -> bool:
    """Return whether a path is a proposal file directly below proposals/."""
    parts = Path(relative_path).parts
    return len(parts) == 2 and parts[0] == "proposals"


def append_document_checks(findings: list[Finding], relative_path: str, text: str) -> None:
    """Append placeholder and line-limit checks shared by non-raw documents."""
    if PLACEHOLDER.search(text):
        findings.append(
            Finding("ERROR", relative_path, "placeholder left in active content")
        )

    line_count = text.count("\n")
    if text and not text.endswith("\n"):
        line_count += 1
    if line_count > MAX_LINES:
        findings.append(
            Finding("WARN", relative_path, f"{line_count} lines exceeds {MAX_LINES}"))


def append_required_collection_checks(
    findings: list[Finding], relative_path: str, frontmatter: dict[str, str] | None
) -> None:
    """Append frontmatter findings for one required collection file."""
    expected_type = REQUIRED_COLLECTION_TYPES[relative_path]
    if frontmatter is None:
        findings.append(Finding("ERROR", relative_path, "missing frontmatter"))
        return

    actual_type = frontmatter.get("type")
    if actual_type not in SUPPORTED_TYPES:
        findings.append(Finding("ERROR", relative_path, "unsupported frontmatter type"))
    elif actual_type != expected_type:
        findings.append(
            Finding("ERROR", relative_path, f"frontmatter type must be {expected_type}")
        )
    elif not frontmatter.get("updated"):
        findings.append(Finding("ERROR", relative_path, "frontmatter missing updated"))


def append_entry_field_findings(
    findings: list[Finding], relative_path: str, entry_id: str, block: str, prefix: str
) -> None:
    """Append required-label and required-value findings for an entry block."""
    fields = fields_in(block)
    missing = sorted(REQUIRED_FIELDS[prefix] - fields.keys())
    if missing:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                f"{entry_id} missing fields: {', '.join(missing)}",
            )
        )

    empty = sorted(
        field for field in REQUIRED_FIELDS[prefix] if field in fields and not fields[field]
    )
    if empty:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                f"{entry_id} empty fields: {', '.join(empty)}",
            )
        )


def lint_active_collection(
    findings: list[Finding],
    definitions: dict[str, str],
    references: list[tuple[str, str]],
    relative_path: str,
    text: str,
) -> None:
    """Validate one active collection and collect its definitions and references."""
    prefix, _ = ACTIVE_COLLECTIONS[relative_path]
    entry_text = FENCED_CODE.sub("", text)
    reference_text = INLINE_CODE.sub("", entry_text)
    references.extend(
        (reference, relative_path) for reference in REFERENCE.findall(reference_text)
    )

    for entry_id, block in entry_blocks(entry_text):
        if not ENTRY_ID.fullmatch(entry_id):
            findings.append(Finding("ERROR", relative_path, f"invalid ID {entry_id}"))
            continue

        if not entry_id.startswith(f"{prefix}-"):
            findings.append(
                Finding(
                    "ERROR",
                    relative_path,
                    f"{relative_path} only accepts {prefix}- entries",
                )
            )
            continue

        if entry_id in definitions:
            findings.append(Finding("ERROR", relative_path, f"duplicate ID {entry_id}"))
        else:
            definitions[entry_id] = relative_path

        append_entry_field_findings(findings, relative_path, entry_id, block, prefix)


def append_proposal_field_findings(
    findings: list[Finding],
    relative_path: str,
    entry_id: str,
    target: str,
    body: str,
) -> None:
    """Validate a proposal candidate without making it an active definition."""
    match = FENCED_MARKDOWN.fullmatch(body)
    if match is None:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                "proposal body must contain exactly one fenced markdown candidate",
            )
        )
        return

    blocks = list(entry_blocks(match.group("candidate")))
    if len(blocks) != 1:
        findings.append(
            Finding("ERROR", relative_path, "proposal candidate must contain one entry")
        )
        return

    candidate_id, candidate_block = blocks[0]
    if candidate_id != entry_id:
        findings.append(
            Finding("ERROR", relative_path, "proposal candidate ID must match entry_id")
        )
        return

    prefix = PROPOSAL_TARGETS.get(target)
    if prefix and ENTRY_ID.fullmatch(candidate_id) and candidate_id.startswith(f"{prefix}-"):
        append_entry_field_findings(
            findings, relative_path, candidate_id, candidate_block, prefix
        )


def lint_dynamic_proposal(
    findings: list[Finding], relative_path: str, text: str
) -> None:
    """Validate one persisted proposal without resolving it as active content."""
    frontmatter = parse_frontmatter(text)
    if frontmatter is None:
        findings.append(Finding("ERROR", relative_path, "missing frontmatter"))
        return

    if set(frontmatter) != PROPOSAL_FIELDS:
        findings.append(
            Finding("ERROR", relative_path, "proposal frontmatter fields are invalid")
        )
    if frontmatter.get("type") != "proposal":
        findings.append(
            Finding("ERROR", relative_path, "proposal frontmatter type must be proposal")
        )
    if not frontmatter.get("updated"):
        findings.append(
            Finding("ERROR", relative_path, "proposal frontmatter missing updated")
        )

    entry_id = frontmatter.get("entry_id", "")
    target = frontmatter.get("target", "")
    if not ENTRY_ID.fullmatch(entry_id):
        findings.append(Finding("ERROR", relative_path, f"invalid ID {entry_id}"))
    elif Path(relative_path).name != f"{entry_id}.md":
        findings.append(
            Finding("ERROR", relative_path, f"proposal filename must be {entry_id}.md")
        )

    prefix = PROPOSAL_TARGETS.get(target)
    if prefix is None:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                "proposal target must be an active collection path",
            )
        )
    elif ENTRY_ID.fullmatch(entry_id) and not entry_id.startswith(f"{prefix}-"):
        findings.append(
            Finding(
                "ERROR", relative_path, "proposal entry_id prefix does not match target"
            )
        )

    append_proposal_field_findings(
        findings, relative_path, entry_id, target, frontmatter_body(text)
    )


def lint(kb: Path) -> list[Finding]:
    """Return deterministic report-only findings for a knowledge-base directory."""
    findings = []
    definitions = {}
    references = []

    for relative_path in sorted(REQUIRED_FILES):
        if not (kb / relative_path).is_file():
            findings.append(Finding("ERROR", relative_path, "required file missing"))

    for path in active_markdown_files(kb):
        relative_path = path.relative_to(kb).as_posix()
        text = path.read_text(encoding="utf-8")
        append_document_checks(findings, relative_path, text)

        if relative_path in REQUIRED_COLLECTION_TYPES:
            frontmatter = parse_frontmatter(text)
            append_required_collection_checks(findings, relative_path, frontmatter)
            if relative_path in ACTIVE_COLLECTIONS:
                lint_active_collection(
                    findings, definitions, references, relative_path, text
                )
        elif is_dynamic_proposal(relative_path):
            lint_dynamic_proposal(findings, relative_path, text)
        else:
            findings.append(Finding("ERROR", relative_path, "unexpected Markdown file"))

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
