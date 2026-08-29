---
name: capture-gotcha
description: Use when the developer explicitly requests recording a resolved ambiguity, correction, or durable knowledge-base entry.
disable-model-invocation: true
---

# Capture Gotcha

This skill is explicitly invoked, never an automatic task wrap-up action.

1. Read `docs/knowledge/README.md` and applicable canonical sources.
2. Select one target: gotcha → `docs/knowledge/gotchas.md`, pin →
   `docs/knowledge/pins.md`, synthesis → `docs/knowledge/syntheses.md`.
   `docs/knowledge/README.md` is schema only, never an active target.
3. Prepare the complete candidate in the target's exact Markdown schema,
   including its `G-`, `PIN-`, or `SYN-` ID and all required fields.
4. If the developer requests show-only or no-write, render the candidate and
   stop. Otherwise, explicit capture authorizes only
   `docs/knowledge/proposals/<semantic-id>.md`, never an active write. Its
   frontmatter is exactly:

   ```yaml
   type: proposal
   entry_id: <semantic-id>
   target: <one active collection path>
   updated: YYYY-MM-DD
   ```

   Its body is one fenced `markdown` block containing the candidate.
5. Show the exact persisted proposal and request approval. It is not authority
   and is excluded from normal consultation.
6. After exact approval, promote the same body to the selected active file,
   remove the proposal file, update `docs/knowledge/INDEX.md` only if routing
   changes, and append the approved capture or promotion to
   `docs/knowledge/log.md`. Make no other writes.

Promotion requires canonical evidence and explicit developer approval. Do not
invent a fact, promote a candidate automatically, archive a rejected proposal,
or make promotion conditional on recurrence. Remove a proposal only with
explicit developer direction or after its approved promotion.
