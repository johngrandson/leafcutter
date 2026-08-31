---
name: calibrate-task
description: Use when planning domain work, resolving semantic ambiguity, applying known corrections, or evaluating an architectural decision; not for commits, pushes, formatting, test execution, or mechanical verification.
---

# Calibrate Task

Use the derived knowledge base only to calibrate a domain decision. It does not
create authority and is read-only.

1. Confirm that `AGENTS.md`, `docs/checkpoint/CURRENT.md`, and the relevant
   canonical documents have already been read.
2. Open `docs/knowledge/INDEX.md`.
3. Load only the derived files that the relevant context route identifies.
4. Compare every derived claim with its cited canonical authority.
5. Report the knowledge that covers the task and any remaining ambiguities.
6. Do not modify `docs/knowledge/log.md` or any other file.

If the canonical sources do not resolve a decision required for the task,
identify the ambiguity and request developer direction before treating it as
settled.
