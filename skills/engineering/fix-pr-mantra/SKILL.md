---
name: fix-pr-mantra
description: Use when addressing pull-request review comments or feedback — "fix the review comments", "address the PR feedback", "go through the comments on this PR", a reviewer (human or bot like CodeRabbit/ultrareview) left comments, or a PR URL is pasted with review feedback to act on. Triggers on /fix-pr-mantra.
---

# Fix PR Mantra

Four-step discipline for turning PR review comments into changes. **Core principle: every comment earns a written verdict before a single line changes, and nothing is edited until the user approves the plan.** Recite the mantra verbatim, then apply the steps in order.

## Recite this — verbatim, as the first thing in your first response

> **Mantra:**
>
> 1. **Every comment earns a verdict.** Gather all of them; none gets silently skipped.
> 2. **Decide before you touch.** Fix, won't-fix, clarify, or defer — each with a reason.
> 3. **Plan, then ask.** Confirm the plan before a single edit.
> 4. **Close every thread you open.** Push after the fix lands, then a one-line receipt per thread — a receipt, not a writeup.

Then begin work.

---

## 1. Gather every comment

Collect the full set of open feedback before reasoning about any of it. The fetch/fact-check
procedure lives in **`ledger-builder.md`** in this skill's directory — one source of truth; what
changes with PR size is only WHO executes it.

- Resolve the PR: the current branch's PR (`gh pr view`), or the number/URL the user gave.
- **Branch guard.** Confirm the checkout is on the PR's head branch (`gh pr view --json headRefName`
  vs `git branch --show-current`) — fact-checks read this code and step 4 commits to it. On a
  different branch → tell the user and get an OK to switch before gathering.
- **Count first** — a cheap query decides who gathers:
  ```sh
  gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){ nodes{ isResolved } }
      }
    }
  }' -F owner=OWNER -F repo=REPO -F pr=NUM
  ```
  Count the `isResolved=false` nodes. The number decides, nothing else.
- **More than 8 unresolved threads:** dispatch ONE `Explore` agent on the `ledger-builder.md`
  contract (pass owner/repo, PR number, and the workspace `gh` prefix). It absorbs the raw
  thread JSON, diffHunks, bot review bodies, and every cited-line file read; you receive only
  the compact ledger — the raw payload never enters your context.
- **8 or fewer:** read `ledger-builder.md` and follow it yourself inline — same fetch,
  pagination, noise filter, fact-check, and ledger shape.
- Either way you now hold the **ledger** (one row per open item, with `thread_id`, location,
  ask, excerpt, `fact_check`). Rows marked `mismatch` get surfaced to the user — don't fabricate
  around code that isn't in this checkout; ask which branch/PR is correct.
- No PR, or no unresolved comments → say so explicitly, and stop.

## 2. Decide a verdict for each comment

Every comment in the ledger gets **exactly one** verdict, and every verdict carries a one-line reason. No comment is left without a verdict.

- **FIX** — valid bug, correctness, security, convention violation, or a concrete requested change.
- **WON'T-FIX** — out of scope, reasoned disagreement, already handled, or a bot false-positive. The reason is mandatory.
- **CLARIFY** — ambiguous, or an open question / design decision. An open question ("should we…?") is answered or asked back, never silently actioned.
- **DEFER** — valid, but belongs in a separate ticket/PR.

A **bot comment is held to the same bar as a human one** — verify the claim against the code before trusting it. "CodeRabbit said so" is not a reason to FIX; "the diff confirms the null path" is.

The ledger's `fact_check` is **evidence for your verdict, not the verdict**: `already-handled` usually argues WON'T-FIX, `mismatch` argues CLARIFY, `confirmed` supports FIX — but the call, and its one-line reason, are yours.

## 3. Plan each fix, then confirm — HARD GATE

- For each **FIX**, write a concrete plan: file(s), the change, test impact, risk.
- Present the **full triage table** to the user — every comment, its verdict, its reason, and the plan for each FIX. The gate is **one plain-text message that ends your turn** — not AskUserQuestion (its checkbox UI truncates the details).
- **Do not edit, commit, or push anything until the user approves.** The user may override any verdict (promote a WON'T-FIX, drop a FIX). This gate holds regardless of how trivial a fix looks or how urgently the merge is wanted.

## 4. Execute, then close the loop

Only after approval:

- Route each FIX to the right tool — **hand off, don't free-hand large edits**:
  - behavior change → **test-driven-development** skill
  - trivial / non-behavioral (doc, comment, rename) → direct edit
  - large / multi-file → dispatch an implementer subagent on the PR branch (implement-task
    Phase-3 style: TDD, code + tests same commit). Do **NOT** invoke the implement-task skill
    end-to-end — it forks a NEW branch and opens a NEW PR; fixes must land on THIS PR's branch.
- **Large fix → Review-Fix loop before push** (implement-task Phase-6 style, on THIS PR branch):
  1. Check the fix diff against the approved triage table — every FIX landed, nothing out of scope.
  2. Invoke `/pr-review-toolkit:review-pr` on the working diff.
  3. Both clean (no gaps, no Critical/Important) → done. Otherwise fix (implementer dispatch for
     substantive, direct for mechanical), re-run the repo's checks, and loop.
  4. Still failing after 3 rounds → stop and take the finding history to the user.
- Verify the changes (build/tests/the repo's checks) **before** touching the PR.
- **Commit & push** to the PR branch.
- **Reply** to each thread via `gh`. A reply is a **receipt, not a writeup** — one line pointing at the change, in this shape:
  - FIX → `Fixed in <sha>: <what changed>.`
  - WON'T-FIX → `Won't fix: <the one-line reason>.`
  - CLARIFY → `<the single question>.`

  The reviewer reads the diff for the how; the reply just says what landed and where.
- **Do not resolve threads** — not even a bot's. Reply, then leave every thread for its reviewer (or the bot's owner) to resolve.

---

## Operating rules

- Recite the mantra block **once**, verbatim, in your first response. Never paraphrase or shorten it.
- If the user says "skip the mantra" → skip the recital but still apply the four steps.
- Strict order: no verdicts before the ledger is complete; no edits before the step-3 gate; no reply/push before the fix is verified.
- The mantra is a constraint **you** carry through the session — not advice to hand back to the user.

## Red flags — STOP and return to the gate

If you catch yourself thinking any of these, you're rationalizing. Stop and follow the step.

| The thought                                                                                  | Why it's wrong                                                                                                                               |
| -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| "Reviewer's waiting — I'll just push the fixes."                                             | A wrong push blocks longer. Triage → confirm → push _is_ the fast path. Speed never skips step 3.                                            |
| "This fix is a one-liner, no need to confirm."                                               | Every edit goes through the gate, however trivial.                                                                                           |
| "Confirming each fix is overhead."                                                           | The gate is one table and one approval, not per-edit nagging.                                                                                |
| "The bot flagged it, so it's real."                                                          | Verify against the code; a bot false-positive burns the same review cycle. Same bar as a human.                                              |
| "I'll handle the ones I'm sure about and skip the confusing one."                            | Every comment earns a verdict; the confusing one is CLARIFY, not skipped.                                                                    |
| "It's an open question, but I'll just build what I think they meant."                        | Open questions are CLARIFY. Doing the wrong thing is the slowest path.                                                                       |
| "Obviously out of scope — I'll ignore it."                                                   | WON'T-FIX with a reason — visible, never silent.                                                                                             |
| "27 threads, but I'll condense the JSON myself — dispatching is overhead."                   | Over 8 unresolved threads the ledger-builder absorbs the payload; your context carries the ledger, not the JSON. The count decides, not you. |
| "I'll resolve the threads while I'm in there." / "It's just a bot thread, I can dismiss it." | Reply, don't resolve — bot threads included. The reviewer (or bot's owner) resolves.                                                         |
