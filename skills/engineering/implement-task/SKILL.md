---
name: implement-task
description: Implement a software task end-to-end — task source to brainstormed plan to test-first code in a worktree to a reviewed, CI-green PR. ALWAYS use when the user asks for a change to be implemented or built, hands over a Jira ID/URL, or points at a plan file.
---

# implement-task

End-to-end workflow for implementing a software task — from a task source
(Jira / plan doc / prompt) to an open PR. Brainstorms with the user, has the approved plan
implemented test-first in a git worktree, then runs a whole-branch Review-Fix loop that repeats
until no Critical/Important findings remain.

You run this as **maker–checker**: implementer subagents write the code, you review it. The
separation is what keeps your Phase 6 judgement independent of the author's blind spots — so it
holds even when you could write the change faster yourself. Either way **you own the outcome**:
delivered work that is wrong is the controller's failure, not the implementer's.

This skill is **project-agnostic**: it carries the _method_, the repo carries the _facts_. In
each repo, discover conventions and commands from the project itself rather than assuming them.

This skill is **procedural and ordered**. Do not skip or reorder phases. Each phase has a
checkpoint. If a change spans multiple repos, run the per-repo phases (2, 3, 4, 5, 6, 7) **once
per repo** — the approved plan (Phase 1) decides which repos those are.

**REQUIRED SUB-SKILLS** — all must be installed; invoke each via the `Skill` tool at the phase that
calls for it, rather than reinventing what it does:
`superpowers:brainstorming` (Phase 1) · `use-worktree` (Phase 2) ·
`superpowers:test-driven-development` (Phase 3) · `superpowers:verification-before-completion`
(Phase 5) · `pr-review-toolkit:review-pr` (Phase 6) · `superpowers:systematic-debugging` (Phase 6,
non-obvious bugs).

## Bundled agent templates (`agents/`)

Some phases are delegated to a **read-only subagent** so the bulky raw output (verification logs, a
Jira ADF payload) is absorbed by the subagent and never bloats your context — you get back a small,
parseable block. The prompt templates live beside this skill in `agents/`:

- `agents/verification-runner.md` — runs the commands it is handed (test suite, or `gh` CI-log commands), returns a fixed evidence block (Phase 5, Phase 6 step 5, and Phase 7).
- `agents/task-source-resolver.md` — resolves a Jira/plan/prompt source, returns distilled task metadata (Phase 0, Jira).

**How to dispatch:** launch the `Explore` subagent (it has `Bash` to run commands but **cannot
Edit/Write** — the read-only profile these need) and pass the template file's body as its prompt.
These files are templates bundled with the skill, **not** auto-registered agent types, so you cannot
pass them as a `subagent_type`.

**The controller keeps the spine — never delegate it:** the worktree path, base branch, branch name,
commit list, task metadata, the plan, and every "done / passing" claim stay with you. A subagent
returns a distilled artifact; **you** decide what it means.

## Hard rules

- **Never** add `Co-Authored-By` or a "Generated with …" footer to commits or PR bodies.
- **Never** `git add -A` / `git add .` — stage files by name. **Never** `--no-verify`,
  `--amend` on existing commits, or `git push --force`.
- **Pause and ask** before any destructive action (force push, `reset --hard`, deleting
  branches, `rm -rf`). If a check fails, fix the root cause — don't bypass with skip flags.
- **Match the repo, don't impose.** Follow the conventions, test style, and commit format the
  repo already uses (read its `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` first).
- **Always use a git worktree** — a **sibling** worktree, outside the repo tree — for all implementation work; never edit files in the main/dev branch.

## Phase 0 — Resolve the task source (auto-detect)

| Signal in the request                                         | Source   | Action                                                                                                                |
| ------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------- |
| Jira ID `[A-Z][A-Z0-9]+-\d+` or `*.atlassian.net/browse/<ID>` | Jira     | Fetch via the Atlassian MCP (`getJiraIssue`). If unreachable, ask the user to paste title + description + issue type. |
| A path to a plan / `.md` file                                 | Plan doc | `Read` it; treat it as the requirement.                                                                               |
| Neither                                                       | Prompt   | Treat the user's prompt as the requirement.                                                                           |

For a **Jira** source, delegate the fetch to the `agents/task-source-resolver.md` template
(dispatched as `Explore`) — the `getJiraIssue` payload is exactly what that template exists to
absorb, and its block is the contract for what comes back. For a **plan doc** or **prompt** source,
resolve inline: nothing bulky to absorb, so a subagent saves nothing.

**Echo back a 2–3 line restatement** and have the user confirm before proceeding. Save the
title, description, type, and any URL for the PR body. With a Jira ID, keep the lowercase form
(`proj-123`) for branches/commits and uppercase (`PROJ-123`) for the PR title.

## Phase 1 — Brainstorm the plan collaboratively with the user

**Invoke the `brainstorming` skill** before writing any code. The brainstorming skill surfaces
the full problem space with the user: it explores intent, requirements, edge cases, design
trade-offs, and unknowns before locking in an approach. This conversation produces a shared
mental model that the user has actively shaped — so the resulting plan reflects their actual
goals rather than your first guess.

The brainstorm output should cover: **which repos the change touches**, files to create/modify
(with paths, grouped by repo), new types/functions, **tests to add**, any docs/spec to update,
and risks / open questions. Track approved sub-tasks with `TodoWrite`. Offer to split large work
into multiple PRs.

Close the plan by proposing the branch name, so a single approval covers both. Infer the prefix
from the task type — Story/Feature → `feature`; Bug → `fix`; Hotfix → `hotfix`; else `chore` —
and propose `<prefix>/<id-or-slug>-<short-desc>` (the same name in every repo for a multi-repo
change).

**Wait for explicit user approval of the plan (including the branch name) before proceeding to
Phase 2.** Treat silence as not approved.

## Phase 2 — sync + branch + worktree (per repo in the plan)

Run any repo-mandated setup first (e.g. an identity/env switch the repo's `CLAUDE.md` requires).
Then, for **each repo the approved plan touches** (never a non-repo parent dir), create the
branch and its worktree directly from the freshly fetched base — **without touching the main
checkout** (no `checkout`/`pull` there: it may hold someone's work in progress, and the worktree
doesn't need it):

Use the **`use-worktree`** skill — run its bundled script (resolve the path relative to that
skill's directory), do NOT reconstruct the git commands inline:

```bash
WT=$(<use-worktree-skill-dir>/scripts/create-worktree.sh <branch> origin/<base>) && cd "$WT"
```

**Chain the `cd` with `&&`** — the script's own contract requires it: on failure it prints nothing
to stdout, so `WT` is empty and a bare `cd ""` succeeds silently, leaving you in the main checkout
and every later phase editing the wrong tree.

The script fetches origin, creates the branch + worktree in one step (main checkout untouched),
and prints the worktree path to stdout. Detect the base branch from the repo (default branch, or
what its docs say — often `main` or `dev`); omit the base argument to use origin's default
branch. The worktree lands at `<repo>.worktrees/<branch-slug>` (`<branch-slug>` = branch with
`/`→`-`) — a **sibling of the repo** (outside its tree) on purpose. Do **not** use
`superpowers:using-git-worktrees` or the native `EnterWorktree` tool, which nest worktrees in
`.claude/worktrees/` _inside_ the repo; a sibling never pollutes the repo's `git status` or
needs a gitignore entry.

Then, **inside `$WT`**, run the project's setup (install deps), detect the verification commands
(test / lint / build / typecheck) from the repo's docs and task runner, and verify a clean test
baseline before implementing. All file edits, test runs, and commits in Phases 3–6 happen inside
`$WT` — never in the main or dev checkout.

## Phase 3 — Implement with tests (code + tests in the same commit)

**Delegate implementation to subagents by default** (maker–checker).

Dispatch one implementer subagent per task in the approved plan (via the `Agent` tool) — use a
repo-specific implementer agent if one exists (e.g. `backend-engineer`), else `general-purpose`.
Hand it the task's requirements, the files it touches, the worktree path, and the repo's
conventions, and require it to follow **`superpowers:test-driven-development`**: test first, then
production code, both in the same commit — every deliverable has coverage from the moment it
exists. It returns a summary plus the commit hash(es) and the test names it added. Dispatch
implementers **one at a time (serial)** — they share the single worktree, so parallel writers
conflict. There is no bundled template for this: unlike the read-only helpers, an implementer
needs Edit/Write, and an existing coding agent already fits.

**Inspect each returned diff before dispatching the next task**: read the commits (`git show`)
against the task's requirement. Wrong approach, missing case, or thin tests → dispatch a
correction with the specific findings. Don't silently patch it yourself — patching makes you the
author of code you must later judge.

**Implement directly yourself only when the entire change is a single small task — one logical
commit touching a few files — where dispatch overhead exceeds the work.** Then follow
`superpowers:test-driven-development` yourself, inside the worktree created in Phase 2.

**Do not invoke `superpowers:subagent-driven-development` here.** SDD is a top-level plan→PR
orchestrator: its flow ends with its own whole-branch review and
`superpowers:finishing-a-development-branch` (which opens a PR). implement-task already owns the
single whole-branch review (Phase 6) and the PR (Phase 7), so nesting SDD duplicates the review and
opens the PR twice. The only review of this work is Phase 6 — reach it with the plan implemented,
tested, and committed.

Whoever writes the code — implementer or you — must read sibling files before inventing a style
(match the existing patterns) and cover the matrix: happy path, every error branch the code
distinguishes, and boundary/validation cases.

- **Write tests at the layer the repo uses** (unit for logic; integration/e2e for flows). Use
  the project's existing test framework and helpers; don't introduce a new one.
- If the change has a UI or an externally observable behavior, add or update an **e2e test**
  using whatever the repo already runs (Playwright/Cypress/etc.).
- Keep any generated/derived files in sync via the project's generator (don't hand-edit
  generated output); stage regenerated files in the same commit as the change that needed them.

Stage files by name (production + test together) and commit each logical chunk using the repo's
commit-message convention (mirror existing history; if the project uses ticket-prefixed messages
like `proj-123: ...`, follow it).

## Phase 4 — Update docs / spec (if the project keeps them in sync)

If the repo maintains specs, FR docs, ADRs, API docs, or a changelog that should reflect this
change, dispatch the update to an implementer subagent (Phase 3 style, same worktree), spelling
out the implemented behavior and anything deferred or divergent so it can annotate honestly.
Phase 3's single-small-task exception does **not** apply to this step: in Phase 6 you judge
whether the doc honestly matches the implemented behavior, and you cannot independently judge
honesty you authored. Skip if the project keeps no such docs. Treat the doc change as part of the
diff under review in Phase 6.

## Phase 5 — Verification (per repo)

Run the **full suite** for each repo — unit, integration, e2e, lint, and a build/typecheck — using
the commands detected in Phase 2. Delegate the run to the `agents/verification-runner.md` template
(dispatched as `Explore`, from inside the worktree); it returns the fixed evidence block its
contract specifies. Do not proceed on a `RED` verdict. If you deliberately skip a layer
(e.g. e2e needs services you can't start locally), **say so explicitly** — never claim "all tests
pass" for a subset.

Apply **`superpowers:verification-before-completion`** to the block it returns: the evidence (command,
exit code, counts, failing log) is what backs any "passing" claim — you (the controller) make the
claim, not the subagent. Assertions without that evidence don't count.

## Phase 6 — Review-fix loop until clean (the core requirement)

This whole-branch Review-Fix loop is **mandatory** and is run by **you (the controller)** — it is
the single review of everything implemented in Phase 3, and it runs **every time**, including when
Phase 3 went smoothly. Any review a subagent did of its own task does **not** substitute for it.

For **each repo**, loop until **both gates pass in the same round**: your own plan-compliance
pass finds nothing (step 1) **and** the review pass reports **no Critical/Important** findings.
(`review-pr` reports severities as **Critical / Important / minor** — there is no "Major" tier.
If the repo's own review command uses different labels, treat its top two severity tiers the same
way.)

### Review-Fix loop

1. **Plan-compliance pass — yours, never delegated.** Read the full branch diff (`git diff <base>...HEAD`) against the approved plan and the task source. Check three things: every plan item landed; nothing out of scope crept in; the behavior matches the spec's intent, not just its letter. The reviewers in step 2 see only the diff — **only you hold the plan**, so drift from it is invisible to them and finding it is your responsibility alone. Count each gap you find as a **Critical** finding in step 3.
2. Invoke `/pr-review-toolkit:review-pr` to review the changes on the current diff (`HEAD` vs base, including any doc changes). If the repo defines its own review command, use that instead.
3. State the combined counts — `Critical: N, Important: M`, where N and M include your step 1 findings — and exit the loop only when **both are 0**. Minor/cosmetic findings never gate a round: fix them while you are already in one (step 4.2), and sweep whatever is left at exit.
4. If there are Critical/Important findings:
   4.1 Plan the fixes yourself. Apply substantive fixes through an implementer dispatch (Phase 3 style) so you stay the checker; a small mechanical fix you may apply directly. When a finding is a bug whose cause isn't obvious, use `superpowers:systematic-debugging`. If a finding raises a question, explore the documentation and codebase for the answer first; ask the user only when genuinely blocked (a missing domain decision, conflicting requirements) — not for routine fixes.
   4.2 Sweep the Minor and cosmetic issues while you are here.
5. Re-run the affected test layers by **re-dispatching the `agents/verification-runner.md` template** (same as Phase 5) so review fixes don't regress behavior.
6. Repeat the loop.

Do not skip step 5: tests must be green **after** each fix round, not just at the start.

**Escape hatch:** if Critical/Important findings persist after **3 full rounds**, or the same
finding keeps reappearing after being fixed (reviewer flip-flop), stop looping and take the
finding history to the user — endless looping burns time without converging.

## Phase 7 — push + open a PR per repo, then teardown

For **each repo** (confirm `gh auth status` and that the repo has a remote before pushing), push
from inside the worktree:

```bash
git push -u origin <branch>
```

**Check for a PR template before composing the body** — `.github/PULL_REQUEST_TEMPLATE.md`,
`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`, or a
`pull_request_template.md` at the repo root (case-insensitive).

- **Template exists** → use it as the body skeleton (`gh pr create --body-file` after filling
  its sections, or reproduce its headings). **The template's structure wins.**
- **No template** → default body: task link (Jira URL or spec reference), one summary bullet per
  logical change, and a reviewer-facing test plan.

Either way: descriptive title (uppercase Jira ID if present), `--base <base>`, **no attribution
footer**. For a multi-repo change, **cross-link the paired PRs** in each body. Use the `gh` CLI.

**Watch CI before tearing down**: `gh pr checks <pr-url> --watch`. If a check fails, get the
failure details by re-dispatching the `agents/verification-runner.md` template with the `gh`
commands: `gh pr checks <pr-url>` (its exit code is the PASS/FAIL evidence) and
`capture: gh run view <run-id> --log-failed` (marked `capture:` because its stdout is the
evidence — the command itself exits 0). The runner's job is "run commands, return evidence", not
only tests, so a CI log belongs in its context rather than yours. Then fix in the worktree (re-running Phase 5/6 as the fix warrants), push again, and re-watch.

Tear down the worktree **last**, once the PR is open and CI is green — raw git, with a path
**byte-identical** to Phase 2's `WT` (shell vars don't persist across steps, so re-derive it
from the `use-worktree` layout, `<repo>.worktrees/<branch-slug>`, with the same `<branch-slug>`):

```bash
ROOT=$(git rev-parse --show-toplevel)   # run from the main checkout
git worktree remove "$(dirname "$ROOT")/$(basename "$ROOT").worktrees/<branch-slug>"
```

Use the plain (non-`--force`) remove: it refuses if uncommitted changes remain — that refusal is
a signal to inspect the worktree, not to force past it. Add `--force` only after
`git -C "$WT" status --short` confirms the tree is clean. The branch lives on with all its
commits — `git worktree remove` deletes only the working directory, never the branch. If the path
drifts from Phase 2's, the stale worktree survives and blocks re-running this task on the same
branch ("already exists").

Return all PR URLs to the user.

## Resuming mid-flow

If re-invoked on the same task, locate the phase per repo from the state on disk, then confirm
"looks like we're at phase N for `<repo>` — continue?" before resuming.

| State found                          | Resume at                                                                                                                     |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| No approved plan from this session   | Phase 1 — re-run `brainstorming`; an unconfirmed plan never becomes code                                                       |
| Plan approved, no branch             | Phase 2                                                                                                                        |
| Branch exists, no worktree, no PR    | Phase 2, with `create-worktree.sh --reuse <branch>` — that flag exists for a resumed run, and the script hard-errors on an existing branch name without it |
| Worktree exists, no commits          | Phase 3                                                                                                                        |
| Commits, tests failing or unrun      | Phase 5                                                                                                                        |
| Green but unreviewed                 | Phase 6                                                                                                                        |
| Reviewed clean, not pushed / no PR   | Phase 7 — if the worktree is already gone, push from the main checkout; the branch still holds every commit                    |
| PR open, CI unwatched                | Phase 7's CI watch                                                                                                             |

## When NOT to use this skill

- Tiny one-line edits the user just wants made and committed — overkill; just make the change.
- Pure research / exploration with no implementable task.
- Work with no clear task source _and_ no described change to implement.
