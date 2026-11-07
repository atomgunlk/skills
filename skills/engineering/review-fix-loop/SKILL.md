---
name: review-fix-loop
description: Use when running repeated review-and-fix rounds on a branch before a push, PR Ready, or merge — a round still has Critical/Important findings, only suggestions remain, the user wants to merge fast, or you must decide what a re-review covers. Triggers on /review-fix-loop.
---

# Review-Fix Loop

## Overview

Review the branch, fix, review again. The loop ends only when a **full** review round finds 0 Critical and 0 Important **on the exact commit you push**. You push once, after the loop ends.

**Clean = a full round with 0 Critical / 0 Important ran on the HEAD you push.**

## What a round reviews

Every round reviews the **whole branch diff against its base** (`git diff <base>...HEAD`). Never only the last fix (`HEAD~1..HEAD`), and never only "the part I changed".

## Each round

1. Review the whole branch diff.
2. Fix every Critical and Important. In the same round, apply the suggestions you accept.
3. Run tests and lint.
4. Commit locally. Do not push.
5. Add one row to the round log: round number, reviewed range (`<base>...<sha>`), Critical/Important count, and each finding by the reviewer's label with its fix and commit.
6. Go back to step 1.

## Ending the loop

A round has 0 Critical and 0 Important. Then pick one:

- **You change nothing more** → the loop ends.
- **You want to apply suggestions** → apply them, then run **one more full round**. Suggestions from that last round are recorded only. They are not applied, because applying them needs another round.

Any code change after the clean round makes that round stale: a suggestion, a new test, a rename, a formatter run. Run one more full round, or do not make the change.

Record every suggestion by the reviewer's label: `fixed`, `declined: <reason>`, or `deferred: <ticket>`.

Then push once. Follow the project's own CI and PR rules.

## Final report

Send the user one message with these parts, in this order:

1. **Result:** the pushed SHA, where it went, and the range of the last clean round.
2. **Rounds:** a table — `Round | Range | C/I | Findings → fix (commit)`. One row per round from the round log, the clean round included.
3. **Suggestions:** each one by label — `fixed (<commit>)`, `declined: <reason>`, `deferred: <ticket>`, or `recorded` for the last round.
4. **Not verified:** test layers not run, and why.
5. **Your call:** the decisions left to the user.

## Time pressure

A round still has a Critical or Important, and the user wants to merge today:

1. Fix it, then run a full round.
2. If that round is clean → push and report.
3. If it finds a new Critical/Important → stop and ask the user. Do not loop on alone. Do not push.

Never tell the user "reviewed" or "ready" when the last review did not cover the whole diff at HEAD.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Earlier rounds cleared the rest. Review only the fix." | A fix can break callers and paths outside its own lines. The reviewer needs the whole diff to see that. |
| "The fix is small, only error handling." | Small fixes on error and money paths are where new bugs start. Full round. |
| "These suggestions are low-risk and do not change behavior." | You decide that without a review. Unreviewed code ships unreviewed. |
| "It is only a new test / a const / sorted imports." | It is a code change after the clean round. Full round, or leave it out. |
| "A full round takes too long; the user wants it today." | A narrow review plus "ready" is a false claim. Run the round, or tell the user what was not reviewed. |
| "If the new test fails, then I re-review." | Re-review comes from the change, not from a failure. |

## Red flags — stop

- The review target is `HEAD~1..HEAD` or "only the fix".
- You edit code after the clean round and then push.
- Your message says "reviewed" but the review did not cover the whole diff at HEAD.
- You push between rounds.
