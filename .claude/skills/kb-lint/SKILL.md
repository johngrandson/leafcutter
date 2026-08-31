---
name: kb-lint
description: Use when the developer explicitly asks to lint, audit, or check the Leafcutter knowledge base.
---

# KB Lint

Run the deterministic report from the workspace root:

```bash
python3 docs/scripts/kb_lint.py --kb docs/knowledge --strict
```

Interpret the report and state its findings, affected files, and any action
that needs developer direction. This skill is report-only: never edit files,
including `docs/knowledge/log.md`.
