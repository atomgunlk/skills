---
name: confluence-writing
description: Use when creating or updating Confluence pages via the Atlassian MCP (createConfluencePage / updateConfluencePage) — especially when an HTML body update is rejected (WAF-blocked), or the page is large and the whole body would have to be re-sent. Symptoms — "update blocked / 403 on updateConfluencePage", "page too large to send back", truncated body risks clobbering a canonical page.
---

# Editing Confluence pages (Atlassian MCP)

## Overview

`updateConfluencePage` **replaces the entire body** and requires the whole body inline in one call. Two hazards follow: WAF blocks on HTML payloads, and pages too large to re-emit.

## Rules

- **HTML body is often WAF-blocked** on update → use `contentFormat: "adf"` (or markdown) instead.
- **Gauge size BEFORE editing.** Fetch the page first. A big page (e.g. a schema page, ~200K+ tokens) **cannot be sent back** (exceeds output budget), and a truncated send clobbers a canonical page.
  - Huge page → do the change via REST `PUT /wiki/api/v2/pages/{id}` with a token (v2 PUT needs the full body **plus** `title` and `version.number` bumped +1 — omit them and it 400/409s), or by hand in the UI. Do NOT try to re-emit the whole body through the MCP tool.
  - Small/medium page → fetch → make surgical edits in a scratch file → send the full body back.
- Bodies can contain smartlink chips / ADF-only nodes with the same markdown round-trip hazard as Jira — see the **jira-writing** skill; the same fetch-ADF → mutate → write-ADF discipline applies.

## Common mistakes

- Sending a partial or truncated body "just to get the edit in" — the page IS the payload; anything missing is deleted.
- Retrying a WAF-blocked HTML update verbatim instead of switching to ADF/markdown.
