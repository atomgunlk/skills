---
name: fix-pr-mantra
description: Use when addressing pull-request review comments or feedback — "fix the review comments", "address the PR feedback", "go through the comments on this PR", a reviewer (human or bot like CodeRabbit/ultrareview) left comments, or a PR URL is pasted with review feedback to act on. Triggers on /fix-pr-mantra.
---

# Fix PR Mantra

Four-step discipline for turning PR review comments into changes. Recite verbatim, then apply in order.

## Recite this — verbatim, as the first thing in your first response

> **Mantra:**
> 1. **Every comment earns a verdict.** Gather all of them; none gets silently skipped.
> 2. **Decide before you touch.** Fix, won't-fix, or clarify — each with a reason.
> 3. **Plan, then ask.** Confirm the plan before a single edit.
> 4. **Close every thread you open.** Reply and push after the fix lands.

Then begin work.

---

## 1. Gather every comment

Collect the full set of open feedback before reasoning about any of it.

- Resolve the PR: the current branch's PR (`gh pr view`), or the number/URL the user gave.
- Fetch **unresolved review threads** with GraphQL — REST omits resolved state:
  ```sh
  gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){ nodes{
          id isResolved isOutdated path line
          comments(first:50){ nodes{ author{login} body createdAt diffHunk } }
        }}
      }
    }
  }' -F owner=OWNER -F repo=REPO -F pr=NUM
  ```
- Also pull general PR comments and review bodies: `gh pr view NUM --json comments,reviews`.
- Keep only `isResolved=false`. Build a **ledger** — one row per comment: id, author (human/bot), `file:line`, the ask, and the cited code context (`diffHunk`).
- **Cross-reference reality:** read the actual file at each cited line. If the comment references code that does not exist in this checkout/PR, do not fabricate it — surface the mismatch and ask which branch/PR is correct.
- No PR, or no unresolved comments → say so explicitly, and stop.

## 2. Decide a verdict for each comment

Every comment in the ledger gets **exactly one** verdict, and every verdict carries a one-line reason. No comment is left without a verdict.

- **FIX** — valid bug, correctness, security, convention violation, or a concrete requested change.
- **WON'T-FIX** — out of scope, reasoned disagreement, already handled, or a bot false-positive. The reason is mandatory.
- **CLARIFY** — ambiguous, or an open question / design decision needing reviewer or user intent. An open question ("should we…?") is answered or asked back, never silently actioned.
- **DEFER** — valid, but belongs in a separate ticket/PR.

A **bot comment is held to the same bar as a human one** — verify the claim against the code before trusting it. "CodeRabbit said so" is not a reason to FIX; "the diff confirms the null path" is.

## 3. Plan each fix, then confirm — HARD GATE

- For each **FIX**, write a concrete plan: file(s), the change, test impact, risk.
- Present the **full triage table** to the user — every comment, its verdict, its reason, and the plan for each FIX.
- **Do not edit, commit, or push anything until the user approves.** The user may override any verdict (promote a WON'T-FIX, drop a FIX). This gate holds regardless of how trivial a fix looks or how urgently the merge is wanted.

## 4. Execute, then close the loop

Only after approval:

- Route each FIX to the right tool — **hand off, don't free-hand large edits**:
  - behavior change → **test-driven-development** skill
  - trivial / non-behavioral (doc, comment, rename) → direct edit
  - large / multi-file → **implement-task** skill
- Verify the changes (build/tests/the repo's checks) **before** touching the PR.
- **Commit & push** to the PR branch.
- **Reply** to each thread via `gh`: `Fixed in <sha>: …` for FIX; the rationale for WON'T-FIX; the question for CLARIFY.
- **Do not resolve threads** — leave resolution to the reviewer.

---

## Operating rules

- Recite the mantra block **once**, verbatim, in your first response. Never paraphrase or shorten it.
- If the user says "skip the mantra" → skip the recital but still apply the four steps.
- Apply the steps **in order**:
  - No verdicts before the ledger is complete (step 1 done).
  - No edits before the user approves the plan (step 3 gate).
  - No reply/push before the fix is verified (step 4).
- The mantra is a constraint **you** carry through the session — not advice to hand back to the user.

## Red flags — STOP and return to the gate

- "The reviewer is waiting, I'll just push the fixes." → Triage and confirm first. Speed is not a reason to skip step 3.
- "This fix is a one-liner, no need to confirm." → Every edit goes through the gate.
- "The bot flagged it, so it must be real." → Verify against the code; bots get a verdict like anyone.
- "I'll address the comments I'm sure about and skip the confusing one." → Every comment earns a verdict; the confusing one is CLARIFY.
- "It's an open question, but I'll just implement what I think they meant." → Open questions are CLARIFY, not FIX.
- "I'll resolve the threads while I'm in there." → Reply, don't resolve. The reviewer resolves.

## Common rationalizations

| Excuse | Reality |
| ------ | ------- |
| "Pushing now unblocks the reviewer faster." | A wrong push blocks longer. Triage → confirm → push is the fast path. |
| "Confirming each fix is overhead." | The gate is one table and one approval, not per-edit nagging. |
| "A bot comment is lower-stakes." | A bot false-positive wastes the same review cycle. Same bar. |
| "The comment is obviously out of scope, I'll just ignore it." | WON'T-FIX with a reason — visible, not silent. |
| "They asked a question; answering is slower than just doing it." | Doing the wrong thing is slowest. CLARIFY. |
