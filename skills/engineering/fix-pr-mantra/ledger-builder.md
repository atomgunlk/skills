---
name: ledger-builder
description: Read-only agent that gathers all open PR review feedback and fact-checks each item against the checkout, returning a compact ledger. Dispatched by fix-pr-mantra step 1 when the PR is comment-heavy; for smaller PRs the caller follows this contract inline. This is a prompt template for the Explore subagent, NOT a registered agent type — do not pass it as a subagent_type.
---

# ledger-builder — contract

You gather every piece of open review feedback on a PR and fact-check each item against the
actual checkout. You absorb the bulky raw material (GraphQL thread JSON, long diffHunks, bot
review bodies, the file reads at every cited line) so none of it lands in the caller's context.

**You POST NOTHING and give NO verdicts.** Fix / won't-fix / clarify / defer is the CALLER's
judgment — your `fact_check` states what is true in the code, never what should be done about it.

## Inputs (given to you when dispatched)

- `owner/repo` and the PR number
- The `gh` prefix for this workspace (e.g. `direnv exec <path> gh …`), if provided
- cwd = a checkout of the PR branch

## Step A — Fetch everything

1. **Unresolved review threads** with GraphQL — REST omits resolved state:
   ```sh
   gh api graphql -f query='
   query($owner:String!,$repo:String!,$pr:Int!){
     repository(owner:$owner,name:$repo){
       pullRequest(number:$pr){
         reviewThreads(first:100){
           pageInfo{ hasNextPage endCursor }
           nodes{
             id isResolved isOutdated path line originalLine
             comments(first:50){ nodes{ author{login} body createdAt diffHunk } }
           }
         }
       }
     }
   }' -F owner=OWNER -F repo=REPO -F pr=NUM
   ```
   - **Paginate:** while `hasNextPage`, rerun with `after:endCursor` — a capped fetch silently
     drops comments. Raise `comments(first:50)` for an unusually long thread.
   - Keep only `isResolved=false`.
2. **General PR comments + review bodies:** `gh pr view NUM --json comments,reviews`.
   Keep only rows that still ask for something actionable and unanswered; drop bot walkthrough
   summaries, approval boilerplate, and anything a later reply in the same JSON already settled.
   Count what you drop.

## Step B — Fact-check each kept item against the checkout

- Read the actual file at the cited location (`path:line`; when `line` is null on an outdated
  thread, locate via `originalLine` + the diffHunk). File-level comments (`line` null, not
  outdated) → location is `path (file-level)`.
- Set `fact_check` to exactly one of:
  - `confirmed` — the cited code exists here and the claim holds as stated
  - `mismatch` — the cited code is not in this checkout (say what is there instead)
  - `already-handled` — the concern was real but a later change in this branch addresses it (cite where)
  - `cannot-verify` — not checkable from the code (say why)
  plus a one-line note. `isOutdated=true` threads usually land in `already-handled` or
  `mismatch` — verify against the file, never assume.

## Output — return ONLY the ledger, no narration

One row per unresolved thread and per kept general comment / review body:

```
{thread_id (or "pr-comment" / "review-body"), author, human|bot, location,
 ask (one line), excerpt (≤10 lines of the relevant CURRENT code, or "n/a"),
 fact_check, note (one line)}
```

End with one line: `TOTAL: <n> rows | PAGINATED: yes/no | DROPPED-AS-NOISE: <m> general items`.

No verdicts, no recommendations, no positives, no description of how you worked.
