---
name: capture-gotcha
description: Use when the developer explicitly requests recording a resolved ambiguity, correction, or durable knowledge-base entry.
disable-model-invocation: true
---

# Capture Gotcha

This skill is explicitly invoked. It never records an entry as an automatic
task wrap-up action.

1. Read `docs/knowledge/README.md` and the applicable canonical sources.
2. Select exactly one active-entry target by type: gotcha →
   `docs/knowledge/gotchas.md`, pin → `docs/knowledge/pins.md`, synthesis →
   `docs/knowledge/syntheses.md`. `docs/knowledge/README.md` is schema and
   reference only, never an active-entry target.
3. Render the complete proposed Markdown body for that target. It must match
   the selected type's exact schema in `docs/knowledge/README.md`, including
   its `G-`, `PIN-`, or `SYN-` ID and every required field. Do not write a
   knowledge base file before developer approval.
4. Ask the developer to approve the exact proposal.
5. Only after approval, update the selected active file; update
   `docs/knowledge/INDEX.md` and `docs/knowledge/log.md` only when needed by
   the approved mutation.

Promotion requires canonical evidence and explicit developer approval. Do not
invent a fact, promote a candidate automatically, or make promotion conditional
on recurrence.
