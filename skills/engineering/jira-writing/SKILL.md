---
name: jira-writing
description: Use when creating or editing Jira issues via the Atlassian MCP (createJiraIssue / editJiraIssue) — composing descriptions and acceptance criteria, bulk-editing or find-replacing across ticket bodies, or when a link must render as an inline smartlink chip (📄 card). Symptoms — "link shows as plain text not a chip", "chips survive a markdown round-trip" (they don't), <custom data-type="smartlink">, ADF vs markdown, renaming a field across ticket bodies, acceptance criteria / EARS notation.
---

# Writing Jira issues (Atlassian MCP)

## Overview

Two facts drive everything here:

1. `editJiraIssue` **replaces the entire description** — there is no append/patch. Always `getJiraIssue` first (someone may have edited it) and send the whole body back.
2. `contentFormat: "markdown"` authors prose, headings, bullets, tables, and code blocks fine — but it **cannot express ADF-only nodes**: smartlink chips (`inlineCard`), mentions, status lozenges, dates, emoji, media. Re-saving a body that contains any of them as markdown silently destroys them.

## Creating a new issue

- `createJiraIssue` with `contentFormat: "markdown"` for plain content. Issue type names vary per project — when unsure, confirm via `getJiraProjectIssueTypesMetadata` / `getJiraIssueTypeMetaWithFields` (also reveals required custom fields) instead of letting the create call fail.
- Description shape: **Context → Acceptance criteria (EARS, see below) → Out of scope**.
- Chip needed in a brand-new issue → author the whole doc as ADF (`contentFormat: "adf"`) from the start.

## Editing — decision rule

Fetch first: `getJiraIssue` `responseContentFormat: "markdown"`.

- Body is plain markdown (no `<custom …>` tags, no mention/emoji artifacts) → edit the markdown, send back with `contentFormat: "markdown"`.
- Body contains **any** `<custom data-type=…>` tag or other non-markdown artifact → re-fetch with `responseContentFormat: "adf"`, mutate **only** the target text nodes, send the **whole doc** back with `contentFormat: "adf"`. Line breaks inside a paragraph are `{"type":"hardBreak"}` nodes. Don't hand-rebuild tables/code blocks in ADF — copy fetched nodes verbatim. The markdown projection is **lossy** (no mention `accountId`, no chip `data-id`) — an ADF edit body can never be reconstructed from markdown; it must be the fetched doc mutated in place.

## The chip — the one thing markdown can't do

An inline smartlink chip (📄 card showing the page title) is ONLY expressible as an ADF `inlineCard` node, placed inline inside a `paragraph`, with **no text child** (Atlassian resolves the title server-side):

```json
{ "type": "inlineCard", "attrs": { "url": "https://site.atlassian.net/wiki/spaces/ABC/pages/123456789" } }
```

Send it with `contentFormat: "adf"` as part of a full `{"type":"doc","version":1,"content":[...]}` document.

## Traps — do NOT do these (all empirically fail)

| What you'll be tempted to do | Reality |
|---|---|
| Put `<custom data-type="smartlink">URL</custom>` in a **markdown** body | That string is a read-side *serialization artifact* of an existing inlineCard, NOT an input syntax. Markdown stores it as literal text → renders as the literal text, never a chip. |
| Trust that it "round-trips" (fetch markdown back, `<custom>` still there) | Round-trip proves nothing — literal text survives a text round-trip *because* it's dumb text. Not proof of a chip. |
| Send a **bare URL** (or `[text](url)`) in markdown and expect auto-convert | Bare-URL→smartlink auto-detect happens in the Jira **UI on paste**, NOT in the MCP markdown→ADF converter. Via the API it stays a plain link. |

**The only path to a chip is an ADF `inlineCard` node.**

## Bulk edits & dispatching to subagents

A field-rename or find-replace **across several tickets whose bodies contain ADF-only nodes** is the exact case this skill exists for — the chip/mention is incidental to your task, so it's easy to treat the edit as "just text" and re-save markdown, silently downgrading every one. It is NOT just text. Also scope the match: case-sensitive, and leave URL slugs / code identifiers (`user-service`) untouched.

When you fan the edits out (one subagent per ticket), **subagents will not discover this skill on their own**. The orchestrator must bake the requirement into each subagent's prompt verbatim:

> Edit via ADF: `getJiraIssue` `responseContentFormat: "adf"` → mutate **only** the target text nodes → `editJiraIssue` `contentFormat: "adf"` sending the whole doc. Never re-save a markdown body that contains `<custom data-type=…>` tags — that renders chips/mentions as literal text. Then verify by re-fetching ADF and confirming the `inlineCard` (and other custom) nodes still exist, and report the verification per ticket.

Don't assume a subagent preserved chips because it reported "done."

## Verify (don't trust round-trip)

"The `<custom>` tag is still there when I re-fetch" and "the chips still look fine" are **NOT** verification. Verify **each edited ticket independently** — confirming one says nothing about the others.

Re-fetch with `responseContentFormat: "adf"`. A real chip is a node `{"type":"inlineCard","attrs":{"url":...}}`. In the markdown projection it shows as `<custom data-type="smartlink" data-id="id-N">` — the **`data-id` is the tell** of a genuine inlineCard (a failed literal-text attempt has no `data-id`). Or look at the Jira UI: 📄 card = worked, literal `<custom...>` text = failed.

## Acceptance criteria — EARS (house style)

Acceptance criteria in a description ARE a list of EARS clauses — one trigger → one testable "shall". Not Given/When/Then, not free-form bullets. If the source material arrives as Gherkin or prose, convert it.

| Pattern | Form | Use for |
|---|---|---|
| Ubiquitous | The system shall … | always-true invariants; regression ("leave X unchanged"); permission-as-rule |
| Event-driven | When \<trigger>, the system shall … | an action / event happens |
| State-driven | While \<state>, the system shall … | during a state (running, offline) |
| Unwanted | If \<condition>, then the system shall … | error / invalid / timeout / reject |
| Optional | Where \<feature configured>, the system shall … | a **configurable/toggleable** feature only |

Example: "Only MANAGER role can export" → *The system shall show the Export action only to users with the MANAGER role.* (Ubiquitous). "Export fails" → *If report generation fails, then the system shall show an error toast.* (Unwanted)

**Gotcha (observed):** permission/role → **Ubiquitous or Event-driven**, NOT `Where`. `Where` is for features that can be turned on/off (config/build flag), not user state or role.

**Converting existing AC → EARS without dropping goals:** map every source item → ≥1 EARS clause; count-in must equal count-covered. Make implicit error/timeout/state cases explicit **Unwanted**/**State-driven** clauses — don't merge them away. Split a compound source bullet into multiple clauses rather than one vague "shall".

## Common mistakes

- Adding a `text` child or a `link` mark to the inlineCard → degrades to a plain hyperlink. inlineCard carries only `attrs.url`.
- Pass the ADF as the parsed `{"type":"doc",…}` **object** — `createJiraIssue` documents a JSON-string form as accepted, but the object form is the one verified to work on both create and edit.
- `blockCard`/`embedCard` = full-width card on its own line; use `inlineCard` for the inline chip.
- Chip renders as raw URL until Jira's resolver fetches the title; the editing account must have permission to view the target page or it degrades to a plain link.
- Guessing `issueTypeName` ("Story" vs localized/renamed types) instead of checking project metadata.

## Related

Confluence page edits (WAF-blocked HTML bodies, whole-body replace, large-page limits) → use the **confluence-writing** skill.
