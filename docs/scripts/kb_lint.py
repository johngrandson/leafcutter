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
ENTRY_ID = re.compile(r"^(?:SYN|G|PIN)-[a-z0-9]+(?:-[a-z0-9]+)+$")
ENTRY_HEADING = re.compile(r"^##[ \t]+(.+?)[ \t]*$", re.MULTILINE)
DOCUMENT_HEADING = re.compile(r"^#[ \t]+.+?[ \t]*$")
ATX_LIKE_HEADING = re.compile(r"^[ \t]*#{1,6}.*$", re.MULTILINE)
COLLECTION_SHARD = re.compile(
    r"^(syntheses|gotchas|pins)/[a-z0-9]+(?:-[a-z0-9]+)*\.md$"
)
REFERENCE = re.compile(r"\[\[((?:SYN|G|PIN)-[^\]]+)\]\]")
FENCE_OPENING = re.compile(r"^[ ]{0,3}(`{3,}|~{3,})")
FENCED_MARKDOWN = re.compile(r"\A\s*```markdown\n(?P<candidate>.*?)```\s*\Z", re.DOTALL)
INLINE_CODE = re.compile(r"`([^`\n]*)`")
DERIVED_ROUTE_ITEM = re.compile(r"^- Derivados:[^\r\n]+$", re.MULTILINE)
MULTI_BACKTICKS = re.compile(r"`{2,}")
SHARD_ROUTE = re.compile(
    r"(?<!`)`(docs/knowledge/(?:syntheses|gotchas|pins)/"
    r"[a-z0-9]+(?:-[a-z0-9]+)*\.md)`(?!`)"
)
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


@dataclass(frozen=True)
class Frontmatter:
    """Parsed fields plus syntax defects from the supported flat format."""

    fields: dict[str, str]
    duplicate_fields: tuple[str, ...]
    malformed_lines: int


def parse_frontmatter(text: str) -> Frontmatter | None:
    """Parse the flat frontmatter subset required by knowledge-base documents."""
    if not text.startswith("---\n"):
        return None

    end = text.find("\n---\n", 4)
    if end == -1:
        return None

    fields = {}
    duplicate_fields = set()
    malformed_lines = 0
    for line in text[4:end].splitlines():
        key, separator, value = line.partition(":")
        key = key.strip()
        if not separator or not key:
            malformed_lines += 1
            continue
        if key in fields:
            duplicate_fields.add(key)
        fields[key] = value.strip()
    return Frontmatter(fields, tuple(sorted(duplicate_fields)), malformed_lines)


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


def fields_in(block: str) -> tuple[dict[str, str], tuple[str, ...]]:
    """Return labeled list fields and duplicate labels from an entry block."""
    fields = {}
    duplicate_fields = set()
    for match in re.finditer(r"^- ([^:\n]+):(.*)$", block, re.MULTILINE):
        field = match.group(1)
        if field in fields:
            duplicate_fields.add(field)
        fields[field] = match.group(2).strip()
    return fields, tuple(sorted(duplicate_fields))


def knowledge_files(kb: Path) -> list[Path]:
    """Return files outside the root raw directory in deterministic order."""
    return [
        path
        for path in sorted(kb.rglob("*"))
        if (path.is_file() or path.is_symlink())
        and path.relative_to(kb).parts[0] != "raw"
    ]


def active_collection_contract(relative_path: str) -> tuple[str, str] | None:
    """Return the semantic prefix and type for a base collection or shard."""
    if relative_path in ACTIVE_COLLECTIONS:
        return ACTIVE_COLLECTIONS[relative_path]

    match = COLLECTION_SHARD.fullmatch(relative_path)
    if match is None:
        return None
    return ACTIVE_COLLECTIONS[f"{match.group(1)}.md"]


def proposal_target_contract(target: str) -> tuple[str, str] | None:
    """Return the active collection contract selected by a proposal target."""
    prefix = "docs/knowledge/"
    if not target.startswith(prefix):
        return None
    return active_collection_contract(target.removeprefix(prefix))


def strip_fenced_code(text: str) -> str:
    """Remove CommonMark-style fenced blocks while preserving line boundaries."""
    result = []
    fence_character = None
    fence_length = 0

    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        if fence_character is None:
            opening = FENCE_OPENING.match(content)
            if opening is None:
                result.append(line)
                continue

            fence = opening.group(1)
            if fence[0] == "`" and "`" in content[opening.end() :]:
                result.append(line)
                continue

            fence_character = fence[0]
            fence_length = len(fence)
        elif re.fullmatch(
            rf" {{0,3}}{re.escape(fence_character)}{{{fence_length},}}[ \t]*",
            content,
        ):
            fence_character = None
            fence_length = 0

        if line.endswith(("\n", "\r")):
            result.append("\n")

    return "".join(result)


def index_route_values(text: str) -> set[str]:
    """Return canonical shard routes declared by root Derivados items."""
    route_values = set()
    for item in DERIVED_ROUTE_ITEM.findall(strip_fenced_code(text)):
        if MULTI_BACKTICKS.search(item):
            continue
        route_values.update(SHARD_ROUTE.findall(item))
    return route_values


def is_dynamic_proposal(relative_path: str) -> bool:
    """Return whether a path is a proposal file directly below proposals/."""
    parts = Path(relative_path).parts
    return len(parts) == 2 and parts[0] == "proposals"


def append_document_checks(findings: list[Finding], relative_path: str, text: str) -> None:
    """Append placeholder and line-limit checks for one active collection."""
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


def append_heading_syntax_finding(
    findings: list[Finding],
    relative_path: str,
    text: str,
    *,
    allow_document_heading: bool,
) -> None:
    """Reject headings outside the active-entry Markdown grammar."""
    document_heading_seen = False
    for match in ATX_LIKE_HEADING.finditer(text):
        line = match.group(0)
        if ENTRY_HEADING.fullmatch(line):
            continue
        if (
            allow_document_heading
            and not document_heading_seen
            and DOCUMENT_HEADING.fullmatch(line)
        ):
            document_heading_seen = True
            continue
        findings.append(Finding("ERROR", relative_path, "invalid heading syntax"))
        return


def append_frontmatter_syntax_findings(
    findings: list[Finding], relative_path: str, frontmatter: Frontmatter
) -> None:
    """Append deterministic findings for malformed or duplicate fields."""
    if frontmatter.malformed_lines:
        findings.append(
            Finding("ERROR", relative_path, "frontmatter contains malformed lines")
        )
    if frontmatter.duplicate_fields:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                "frontmatter duplicate fields: "
                + ", ".join(frontmatter.duplicate_fields),
            )
        )


def append_collection_frontmatter_checks(
    findings: list[Finding],
    relative_path: str,
    frontmatter: Frontmatter | None,
    expected_type: str,
) -> None:
    """Append frontmatter findings for one schema-controlled document."""
    if frontmatter is None:
        findings.append(Finding("ERROR", relative_path, "missing frontmatter"))
        return

    append_frontmatter_syntax_findings(findings, relative_path, frontmatter)
    actual_type = frontmatter.fields.get("type")
    if actual_type not in SUPPORTED_TYPES:
        findings.append(Finding("ERROR", relative_path, "unsupported frontmatter type"))
    elif actual_type != expected_type:
        findings.append(
            Finding("ERROR", relative_path, f"frontmatter type must be {expected_type}")
        )
    elif not frontmatter.fields.get("updated"):
        findings.append(Finding("ERROR", relative_path, "frontmatter missing updated"))


def append_entry_field_findings(
    findings: list[Finding], relative_path: str, entry_id: str, block: str, prefix: str
) -> None:
    """Append required-label and required-value findings for an entry block."""
    fields, duplicate_fields = fields_in(block)
    if duplicate_fields:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                f"{entry_id} duplicate fields: {', '.join(duplicate_fields)}",
            )
        )

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
        field
        for field in REQUIRED_FIELDS[prefix]
        if field in fields
        and not INLINE_CODE.sub(lambda match: match.group(1), fields[field]).strip()
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
    contract = active_collection_contract(relative_path)
    if contract is None:
        raise ValueError(f"missing active collection contract for {relative_path}")

    prefix, _ = contract
    append_document_checks(findings, relative_path, text)
    entry_text = strip_fenced_code(text)
    append_heading_syntax_finding(
        findings,
        relative_path,
        entry_text,
        allow_document_heading=True,
    )
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

    candidate = match.group("candidate")
    if PLACEHOLDER.search(candidate):
        findings.append(
            Finding("ERROR", relative_path, "placeholder left in candidate content")
        )

    if ENTRY_HEADING.match(candidate.lstrip()) is None:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                "proposal candidate must start with its entry",
            )
        )
        return

    append_heading_syntax_finding(
        findings,
        relative_path,
        candidate,
        allow_document_heading=False,
    )

    blocks = list(entry_blocks(candidate))
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

    contract = proposal_target_contract(target)
    if (
        contract
        and ENTRY_ID.fullmatch(candidate_id)
        and candidate_id.startswith(f"{contract[0]}-")
    ):
        append_entry_field_findings(
            findings, relative_path, candidate_id, candidate_block, contract[0]
        )


def lint_dynamic_proposal(
    findings: list[Finding],
    relative_path: str,
    text: str,
    kb: Path,
    index_routes: set[str],
) -> None:
    """Validate one persisted proposal without resolving it as active content."""
    frontmatter = parse_frontmatter(text)
    if frontmatter is None:
        findings.append(Finding("ERROR", relative_path, "missing frontmatter"))
        return

    append_frontmatter_syntax_findings(findings, relative_path, frontmatter)
    fields = frontmatter.fields
    if set(fields) != PROPOSAL_FIELDS:
        findings.append(
            Finding("ERROR", relative_path, "proposal frontmatter fields are invalid")
        )
    if fields.get("type") != "proposal":
        findings.append(
            Finding("ERROR", relative_path, "proposal frontmatter type must be proposal")
        )
    if not fields.get("updated"):
        findings.append(
            Finding("ERROR", relative_path, "proposal frontmatter missing updated")
        )

    entry_id = fields.get("entry_id", "")
    target = fields.get("target", "")
    if not ENTRY_ID.fullmatch(entry_id):
        findings.append(Finding("ERROR", relative_path, f"invalid ID {entry_id}"))
    elif Path(relative_path).name != f"{entry_id}.md":
        findings.append(
            Finding("ERROR", relative_path, f"proposal filename must be {entry_id}.md")
        )

    contract = proposal_target_contract(target)
    if contract is None:
        findings.append(
            Finding(
                "ERROR",
                relative_path,
                "proposal target must be an active collection path",
            )
        )
    elif ENTRY_ID.fullmatch(entry_id) and not entry_id.startswith(f"{contract[0]}-"):
        findings.append(
            Finding(
                "ERROR", relative_path, "proposal entry_id prefix does not match target"
            )
        )

    if contract is not None:
        target_path = target.removeprefix("docs/knowledge/")
        if target_path not in ACTIVE_COLLECTIONS:
            shard = kb / target_path
            if not shard.is_file() or shard.is_symlink():
                findings.append(
                    Finding(
                        "ERROR",
                        relative_path,
                        "proposal target shard does not exist",
                    )
                )
            elif target not in index_routes:
                findings.append(
                    Finding(
                        "ERROR",
                        relative_path,
                        "proposal target shard is not routed by INDEX.md",
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
    documents = {}

    for relative_path in sorted(REQUIRED_FILES):
        if not (kb / relative_path).is_file():
            findings.append(Finding("ERROR", relative_path, "required file missing"))

    for path in knowledge_files(kb):
        relative_path = path.relative_to(kb).as_posix()
        if path.is_symlink():
            findings.append(
                Finding("ERROR", relative_path, "symbolic links are not allowed")
            )
            continue
        if path.suffix != ".md":
            findings.append(
                Finding("ERROR", relative_path, "unexpected knowledge file")
            )
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            findings.append(Finding("ERROR", relative_path, "invalid UTF-8"))
            continue
        documents[relative_path] = text

    index_routes = index_route_values(documents.get("INDEX.md", ""))
    for relative_path, text in documents.items():
        if relative_path in REQUIRED_COLLECTION_TYPES:
            frontmatter = parse_frontmatter(text)
            append_collection_frontmatter_checks(
                findings,
                relative_path,
                frontmatter,
                REQUIRED_COLLECTION_TYPES[relative_path],
            )
            if relative_path in ACTIVE_COLLECTIONS:
                lint_active_collection(
                    findings, definitions, references, relative_path, text
                )
        elif contract := active_collection_contract(relative_path):
            frontmatter = parse_frontmatter(text)
            append_collection_frontmatter_checks(
                findings, relative_path, frontmatter, contract[1]
            )
            target = f"docs/knowledge/{relative_path}"
            if target not in index_routes:
                findings.append(
                    Finding(
                        "ERROR",
                        relative_path,
                        "collection shard is not routed by INDEX.md",
                    )
                )
            lint_active_collection(
                findings, definitions, references, relative_path, text
            )
        elif is_dynamic_proposal(relative_path):
            lint_dynamic_proposal(findings, relative_path, text, kb, index_routes)
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
