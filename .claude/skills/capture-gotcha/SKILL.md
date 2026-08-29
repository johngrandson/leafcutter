---
name: capture-gotcha
description: Use when the developer explicitly requests recording a resolved ambiguity, correction, or durable knowledge-base entry.
disable-model-invocation: true
---

# Capture Gotcha

This skill is explicitly invoked. It never records an entry as an automatic
task wrap-up action.

1. Read `docs/knowledge/README.md` and the applicable canonical sources.
2. Render the complete text of the proposed entry in the response, including
   its target file, context, claim, and canonical evidence. Do not write a
   knowledge base file before developer approval.
3. Ask the developer to approve the exact proposal.
4. Only after approval, update the applicable active file in
   `docs/knowledge/gotchas.md`, `docs/knowledge/pins.md`, or
   `docs/knowledge/syntheses.md`; update `docs/knowledge/INDEX.md` and
   `docs/knowledge/log.md` only when needed by the approved mutation.

Promotion requires canonical evidence and explicit developer approval. Do not
invent a fact, promote a candidate automatically, or make promotion conditional
on recurrence.
