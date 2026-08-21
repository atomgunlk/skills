---
name: jira-writing
description: Use when creating or editing Jira issues via the Atlassian MCP (createJiraIssue / editJiraIssue) — composing descriptions and acceptance criteria, bulk-editing or find-replacing across ticket bodies, or when a link must render as an inline smartlink chip (📄 card). Symptoms — "link shows as plain text not a chip", "chips survive a markdown round-trip" (they don't), <custom data-type="smartlink">, ADF vs markdown, renaming a field across ticket bodies, acceptance criteria / Given-When-Then AC table (AC No., Scenario, Given, When, Then/And).
---

# Writing Jira issues (Atlassian MCP)

## Overview

Two facts drive everything here:

1. `editJiraIssue` **replaces the entire description** — there is no append/patch. Always `getJiraIssue` first (someone may have edited it) and send the whole body back.
2. `contentFormat: "markdown"` authors prose, headings, bullets, tables, and code blocks fine — but it **cannot express ADF-only nodes**: smartlink chips (`inlineCard`), mentions, status lozenges, dates, emoji, media. Re-saving a body that contains any of them as markdown silently destroys them.

## Creating a new issue

- `createJiraIssue` with `contentFormat: "markdown"` for plain content. Issue type names vary per project ("Story" vs localized or renamed types) — when unsure, confirm via `getJiraProjectIssueTypesMetadata` / `getJiraIssueTypeMetaWithFields` (also reveals required custom fields) instead of guessing `issueTypeName` and letting the create call fail.
- Description shape: **Context → Acceptance criteria (AC table, see below) → Out of scope**.
- Chip needed in a brand-new issue → author the whole doc as ADF (`contentFormat: "adf"`) from the start.

## Acceptance criteria — AC table (house style)

Acceptance criteria in a description ARE a markdown table — **one row per AC, five columns**. Not "shall" clauses, not free-form bullets. If the source arrives as EARS, prose, or Gherkin `Scenario:` blocks, convert it into rows (a Gherkin `Scenario:` title maps straight onto the `Scenario` column).

| AC No. | Scenario | Given | When | Then/And |
|---|---|---|---|---|
| AC1 | Manager sees Export | user has the MANAGER role | user opens the report page | Then the Export action is visible |
| AC2 | Export hidden for others | user has a non-MANAGER role | user opens the report page | Then the Export action is hidden |
| AC3 | Export succeeds | user has the MANAGER role | the export completes | Then the file downloads. And the export is written to the activity log. |
| AC4 | Generation failure | a valid report request | report generation fails | Then an error toast is shown |

- **AC No.** — `AC1`, `AC2`, … `AC13`, `AC14` — no dash, no zero-padding, double digits stay bare. Unique within the ticket. Numbers are **stable IDs**: when editing an existing table, add new ACs at the next free number and leave removed ones as gaps. Never renumber — QA test cases and comments reference `AC3` by name.
- **Scenario** — a 3–6 word label naming the case (`Manager sees Export`, `Expired token`, `Empty result set`). A handle for the row, not a restatement of Given/When.
- **Given** — the precondition that must hold: role, state, feature flag, existing record. Write `—` when there genuinely is none.
- **When** — the single observable trigger (`user opens the report page`, `the download completes`), never a fake `always`.
- **Then/And** — the outcomes of that one trigger, each keyword-prefixed: `Then <outcome>`, then `And <outcome>` for each further assertion of the **same** trigger. `And` is optional — most rows are a single `Then`. **Keep the cell on one line:** `Then the file downloads. And the export is written to the activity log.` A markdown table cell cannot hold a line break, and every workaround makes the ticket ADF-only forever (below).

**An invariant AC still needs an observable `Then`.** "unchanged", "same as today", "no impact", "behaves as before" are not testable — a tester cannot run them. Name the observable that would differ if the invariant broke — the reading, count, ordering, or field values a tester can compare: not `Then the existing search ranking is unaffected`, but `Then the first page still returns the same 20 results in the same order for the query "term life"`. An invariant is also a regression guard, so give it **its own AC No.** rather than an `And` under the happy path — buried under a passing scenario it drops out of test planning.

**One trigger per AC No.** `And` only ever adds a second assertion about the same `When`. Error / timeout / permission denied / empty or invalid input each get **their own AC No.**, never an `And` line under the happy path. A compound source bullet becomes several ACs.

**Converting existing AC → rows without dropping goals:** map every source item → ≥1 AC No.; count-in must equal count-covered.

### Multi-line cells are ADF-only — and they break markdown editing

Probed empirically against the Atlassian MCP. All three were tried; none is safe for a markdown-edited ticket:

| Attempt | What actually happens |
|---|---|
| `<br>` or `<br/>` inside a **markdown** cell | Stored as literal text and HTML-escaped on render (`&lt;br&gt;`) — the reader sees `Then X<br>And Y`. Same failure class as the smartlink trap below. |
| ADF `hardBreak` in the cell's paragraph | Renders correctly (`<br/>`). But the markdown projection is two trailing spaces + a **real newline inside the table row** — re-saving that markdown **corrupts the table**: the row splits into a broken extra row and the text loses its leading character (`And outcome two` came back as `nd outcome two`). |
| ADF: two `paragraph` nodes in one `tableCell` | Renders correctly (`<br/>`). But the markdown projection silently **flattens it to one line** joined by a space — a markdown re-save drops the break with no error. |

A table with even one multi-line cell makes the **whole description ADF-only for the rest of its life** — every future edit must fetch and send ADF. Take that on deliberately or not at all; the one-line cell above costs nothing.

## Editing — decision rule

Fetch first: `getJiraIssue` `responseContentFormat: "markdown"`.

- Body is plain markdown (no `<custom …>` tags, no mention/emoji artifacts) → edit the markdown, send back with `contentFormat: "markdown"`.
- Body contains **any** `<custom data-type=…>` tag or other non-markdown artifact → re-fetch with `responseContentFormat: "adf"`, mutate **only** the target text nodes, send the **whole doc** back with `contentFormat: "adf"`. Line breaks inside a paragraph are `{"type":"hardBreak"}` nodes. Don't hand-rebuild tables/code blocks in ADF (AC tables included) — copy fetched nodes verbatim and mutate the cell text in place. The markdown projection is **lossy** (no mention `accountId`, no chip `data-id`) — an ADF edit body can never be reconstructed from markdown; it must be the fetched doc mutated in place.

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

A field-rename or find-replace **across several tickets whose bodies contain ADF-only nodes** is the exact case this skill exists for — the chip/mention is incidental to your task, so it's easy to treat the edit as "just text". It is NOT just text. Also scope the match: case-sensitive, and leave URL slugs / code identifiers (`user-service`) untouched.

When you fan the edits out (one subagent per ticket), **subagents will not discover this skill on their own**. The orchestrator must bake the requirement into each subagent's prompt verbatim:

> Edit via ADF: `getJiraIssue` `responseContentFormat: "adf"` → mutate **only** the target text nodes → `editJiraIssue` `contentFormat: "adf"` sending the whole doc. Never re-save a markdown body that contains `<custom data-type=…>` tags — that renders chips/mentions as literal text. Then verify by re-fetching ADF and confirming the `inlineCard` (and other custom) nodes still exist, and report the verification per ticket.

Don't assume a subagent preserved chips because it reported "done."

## Verify (don't trust round-trip)

Verify **each edited ticket independently** — confirming one says nothing about the others.

Re-fetch with `responseContentFormat: "adf"`. A real chip is a node `{"type":"inlineCard","attrs":{"url":...}}`. In the markdown projection it shows as `<custom data-type="smartlink" data-id="id-N">` — the **`data-id` is the tell** of a genuine inlineCard (a failed literal-text attempt has no `data-id`). Or look at the Jira UI: 📄 card = worked, literal `<custom...>` text = failed.

## Common mistakes

- Adding a `text` child or a `link` mark to the inlineCard → degrades to a plain hyperlink. inlineCard carries only `attrs.url`.
- Pass the ADF as the parsed `{"type":"doc",…}` **object** — `createJiraIssue` documents a JSON-string form as accepted, but the object form is the one verified to work on both create and edit.
- `blockCard`/`embedCard` = full-width card on its own line; use `inlineCard` for the inline chip.
- Chip renders as raw URL until Jira's resolver fetches the title; the editing account must have permission to view the target page or it degrades to a plain link.

## Related

Confluence page edits (WAF-blocked HTML bodies, whole-body replace, large-page limits) → use the **confluence-writing** skill.
