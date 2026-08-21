---
name: pr-review-inline
description: >
  Review a GitHub Pull Request and post every finding as an inline, line-level
  comment on the changed code — line comments only, not a summary comment.
  Use when the user asks to review a PR and comment in the code, says
  "รีวิว PR แล้ว คอมเมนต์ในโค้ด", or hands over a PR number/URL to review.
argument-hint: "[PR number or URL]"
---

# /pr-review-inline

Review a GitHub PR with `/pr-review-toolkit:review-pr`, then post each finding as an **inline line comment** (with a fix suggestion) on the exact problematic line. Line comments only.

Follow every step in order. Posting to a PR is outward-facing: post only the findings the user picks at the Step 8 selection gate.

**REQUIRED SUB-SKILL:** `use-worktree` (bundled in this repo) — Steps 3 and 5 use its `scripts/create-worktree.sh`. Installing pr-review-inline alone will fail at Step 3; install both.

## Personalize (fill before first use)

The steps reference these placeholders — replace the example column with your values.

| Placeholder | Meaning | Example |
|---|---|---|
| `<gh-wrapper>` | Prefix required for `gh` in your workspace (empty if none) | `direnv exec ~/workspace/acme` |
| `<jira-site>` | Your Atlassian site (Step 2) | `acme.atlassian.net` |
| `<ticket-regex>` | Ticket-key pattern extracted from the PR title/body | `ABC-\d+` |

**Review voice** — Steps 7–8 write comment bodies and the closing ask in *your* review voice; replace this worked example with your own:

- Bilingual Thai + English, terse — usually one short line. English for imperatives and technical terms; Thai for reasoning. Code identifiers stay English.
- Direct but softened — Thai particles `ครับ`/`คับ`/`นะ`, or English `please`.
- Prefer a question to push back when reconsideration is the point (`ทำไมเก็บ Number เป็น string`, `ใช้จาก appConfig ได้ไหมครับ`).
- Optional findings marked in the body: `optional นะครับ` / `(optional)`.
- Step-8 closing ask, e.g.: `เลือกหมายเลขที่จะให้ post ได้เลยครับ (เช่น "1 3 4", "1-3", "all", "none") — แนะนำ 1-2 (🔴/🟠)`

## Plain dispatch (reference for Steps 2, 4 and 6 — not a step)

Every subagent in this skill (Steps 2, 4, 6) is a **plain dispatch**: one `Agent` call with a `subagent_type`, no `name`, not backgrounded, so its result arrives as that call's own tool result. Several plain dispatches in ONE message run in parallel. A named or backgrounded agent instead reports through a mailbox you cannot collect — `TaskOutput` wants a task id, while the spawn result only prints an `agent_id` (`<name>@session-…`), so joining one yields `No task found with ID: <name>@session-…` and ends in a re-dispatch.

## Step 1 — Resolve the PR and preconditions

0. **`gh` wrapper.** If `<gh-wrapper>` (Personalize) is non-empty, use it for EVERY `gh` command in this skill and pass it to every subagent prompt as "the gh prefix".
1. Parse the argument:
   - Full URL → `owner/repo` + PR number.
   - Bare number → PR number; `owner/repo` comes from the clone resolved in item 2.
   - No argument → the PR must be resolved from the current branch, so cwd must already be inside the repo clone; if cwd is not a git repo, print a clear error asking for a PR number/URL and STOP.
2. **Locate the PR's repo clone (or fail fast) + capture its root.** The review needs a local clone of the PR's repo. If cwd isn't it (cwd is often a parent dir, not a git repo), search the workspace for a clone whose `origin` matches the PR's `owner/repo` (e.g. `~/workspace/**/<repo>`) and `cd` into it. **If no matching clone is found, or cwd / the resolved dir is a *different* repo than the PR → print a clear error naming the expected `owner/repo`, tell the user, and STOP the skill** (do NOT auto-clone, do NOT continue). Only once a matching clone is confirmed, capture the root: `ROOT=$(git rev-parse --show-toplevel)`. Bare number → resolve `owner/repo` here with `gh repo view --json nameWithOwner`; no argument → resolve the PR number here with `gh pr view --json number`. No clean-tree requirement — Step 3 reviews inside an isolated **sibling** `git worktree` (created next to the repo, not inside it), so the user's branch, working tree, and untracked files are never touched.
3. Read the PR:
   ```bash
   gh pr view "$PR" --json number,title,body,headRefOid,headRefName,baseRefName,url
   ```
   Save `headRefOid` (= `HEAD_SHA`, the commit comments anchor to) and `baseRefName` (= `BASE`).

## Step 2 — Ask about the Jira ticket (BEFORE reviewing)

Extract a Jira key from the PR title+body: `<ticket-regex>` or `<jira-site>/browse/<KEY>`.

If a key is found, **ask the user**: read Jira ticket `<KEY>` as review context? (default: yes if found)

- If yes: **plain-dispatch the `task-source-resolver` template — `subagent_type: Explore`, `model: sonnet` — and wait for it here, before Step 3.** Its returned message IS the ticket context, so there is nothing to join, poll, or fetch afterwards. The Jira payload (description + comment thread) never enters the main context — only the resolver's distilled block does. Dispatch prompt:
  > Read `<implement-task skill dir>/agents/task-source-resolver.md` (the `implement-task` skill directory, sibling of this skill's) and follow it EXACTLY. Input: Jira `<KEY>`. Call `getJiraIssue` with `cloudId` = `<jira-site>` directly (no `getAccessibleAtlassianResources`).

  When it returns, apply these caller rules:
  - `NOTES` reports fetch failure / MCP tools missing → **STOP the skill** (nothing to clean up — this runs before the Step-3 worktree exists): tell the user to run `/reload-plugins` (MCP tools register only at session start — enabling/authing mid-session alone won't surface them) and re-run. Do NOT fall back to WebFetch (`<jira-site>` is private and WebFetch fails on it) or to pasting; do NOT continue the review without the ticket.
  - Otherwise: use `TITLE`, `DESCRIPTION`, and `COMMENTS` as review context in Step-4 prompts — comments often change a ticket's direction, so trust `SUPERSEDES:` entries over the description. Ignore `RESTATEMENT`/`TYPE`. Never expand review scope beyond the PR diff.
- If no key found, or the user declines: continue without it (no MCP needed).

## Step 3 — Expose the PR as a reviewable local diff (isolated worktree)

`review-pr` reviews the local **working-tree `git diff`**, not a remote PR. Do the checkout in a throwaway **sibling git worktree** — placed *next to* the repo, not inside it — so the user's own checkout (branch, working tree, untracked files) is never touched:

Create the checkout with the **`use-worktree`** skill's bundled script in **detached mode** (resolve the path relative to that skill's directory — do NOT reconstruct the worktree git commands inline), then bridge the diff:

```bash
git fetch origin "pull/$PR/head" "$BASE"
MB=$(git merge-base "$HEAD_SHA" "origin/$BASE")
WT=$(<use-worktree-skill-dir>/scripts/create-worktree.sh --detach "$HEAD_SHA" "review-pr-$PR")
cd "$WT"
git reset "$MB"                                    # mixed reset: PR changes become UNSTAGED here
git add -N .                                       # intent-to-add: files the PR ADDED show in git diff (without this they are untracked = INVISIBLE to the review)
```

The worktree lands at `<repo>.worktrees/review-pr-$PR` — a **sibling of the repo**, outside its tree.

**Why a sibling (not nested inside `$ROOT`):** an in-tree worktree would pollute the reviewed repo's `git status` unless a `git check-ignore` + gitignore-commit safety step is added — a step this skill would otherwise skip. A sibling lives outside the repo tree, so that whole safety step becomes unnecessary and the reviewed repo is never touched at all.

**Guard — bridge worked.** Run `git diff --stat` (inside the worktree). If it is EMPTY, STOP (the bridge misfired; otherwise `review-pr` silently reviews nothing and a broken pipe reads as "clean PR"). With `git add -N` in place even a pure-file-addition PR yields a non-empty diff, so empty genuinely means misfire. Now `git diff` shows exactly the PR's changes and the session cwd is the worktree, so `review-pr` (Step 4) reviews it.

## Step 4 — Run the review (read review-pr's roster, then dispatch — scaled to PR size)

`/pr-review-toolkit:review-pr` is a natural-language command: invoking it returns a **workflow/roster description, NOT findings** — it does not run any agents. Invoke it, then **read its output as the live source of truth** for which specialist agents exist and which aspect each covers. The toolkit updates often, so trust its output over any hardcoded list.

```
/pr-review-toolkit:review-pr code errors types tests comments parallel
```

Then **plain-dispatch the applicable agents yourself, in parallel**, scaling the count to the PR's size/risk to save tokens (agents are ~90% of this skill's cost):

- **Tiny** — ≤2 changed code files AND ≤~80 changed lines AND no risky path (auth, money/payment, SQL/migrations, crypto, concurrency): dispatch **`code-reviewer` only** (+ `pr-test-analyzer` iff test files changed). Do NOT fan out.
- **Medium** (default): `code-reviewer` + the agents whose aspect actually changed, per review-pr's aspect→agent map (tests→pr-test-analyzer, comments/docs→comment-analyzer, error handling→silent-failure-hunter, new types→type-design-analyzer).
- **Large / risky** (many files, large diff, or touches a risky path): the full applicable set.
- Never dispatch `simplify` / `code-simplifier` — it MUTATES code. If review-pr lists an agent not in the fallback below, still consider it (that's why we read its output).

Fallback roster if review-pr's output is unavailable: `code-reviewer` (always), `pr-test-analyzer` (tests), `comment-analyzer` (comments/docs), `silent-failure-hunter` (error handling), `type-design-analyzer` (new types). **Dispatch with the full `subagent_type`** — these agents live under the plugin namespace, e.g. `pr-review-toolkit:code-reviewer`; the short name alone fails.

**Model per agent** (override via the Agent tool; default inherits the session model):
- `code-reviewer`, `silent-failure-hunter` → keep the session model — correctness-critical, do NOT downgrade.
- `pr-test-analyzer`, `type-design-analyzer` → `sonnet`.
- `comment-analyzer` → `haiku`.

Each agent prompt MUST include: the repo + PR intent + the Step-2 Jira context (TITLE / DESCRIPTION / COMMENTS, if fetched); the **worktree cwd** and that `git diff` there shows exactly the PR's changes; an instruction to read the changed files in full. **Require terse output** — return ONLY actionable findings as a compact list, each `{severity, file, NEW-file line (RIGHT side), one-line problem, one-line fix}`; no positives, no "not a defect / confirmed safe" notes, no narration of how the review was done; order by severity and return the top ~8, and **if the agent found more, it must close with `CUT: <n> more below this bar`** so the truncation reaches the Step-8 gate as a visible count instead of a silent drop; end with "your final message IS the data I consume — return the findings list directly." (The agent still reasons fully — only its final message must be terse; its reasoning never enters your context anyway.) Collect every agent's output and dedupe across them (findings on the same file:line often overlap), carrying each agent's `CUT: <n>` through the dedupe untouched — those are counts, not findings, and Step 8 reports their total. **This deduped raw-findings list is the ONLY input the Step 6 anchor-verifier needs from the review** — the raw diff itself never has to enter your context.

## Step 5 — Tear down the worktree

Posting uses the PR head SHA + file paths and does not depend on local git state, so clean up now:

```bash
cd "$ROOT"
git worktree remove --force "$ROOT.worktrees/review-pr-$PR"   # use-worktree layout — byte-identical to Step 3's WT; --force: worktree holds the dirty reset state
```

No branch to delete — the worktree was detached. The user's checkout was never modified. The sibling path here **must match Step 3's `WT` exactly** (`$WT` does not survive across shell calls); if it drifts, the stale worktree survives and breaks the next review of this PR with "already exists".

## Step 6 — Anchor & verify findings (dispatch the anchor-verifier subagent)

The raw findings from Step 4 are unverified and unanchored. Building the commentable line-set (parsing the full `gh pr diff`) and verifying each finding against the head file are **token-heavy, mechanical, self-contained** work — so push them into ONE dedicated subagent instead of doing them in the main context. The subagent absorbs the raw diff + head files; you get back only three small structured lists (COMMENTS / UN-ANCHORABLE / DROPPED). **This is the context firewall that keeps the raw diff (often tens of KB) out of the main thread** where it would otherwise persist through the rest of the run.

**Plain-dispatch ONE agent** — `general-purpose`, **keep the session model** (verification of Critical claims is correctness-critical; do NOT downgrade). It runs AFTER teardown (Step 5), so the worktree is gone — it must read source via `git show "$HEAD_SHA":<path>` (works with no checkout), NOT worktree files. **It posts nothing — its final message returns data.**

A whole-file, type-level, or missing-test finding has no diff line to sit on: it belongs on the verifier's UN-ANCHORABLE list, reported in the terminal (Steps 8 and 10) and never forced onto a nearby line, where it would 422 or land on unrelated code.

The agent's full contract lives in **`anchor-verifier.md`** in this skill's own directory (next to this file) — keeping it out of `SKILL.md` means the contract body never enters the main context either. Dispatch prompt = the inputs + a pointer to that file:

> Read `anchor-verifier.md` in the `pr-review-inline` skill directory (`<this skill's absolute path>/anchor-verifier.md`) and follow it EXACTLY. It posts nothing; return the three lists it specifies.
>
> Inputs: `owner/repo` = …, `PR` = …, `HEAD_SHA` = …, `BASE` = …, gh prefix = … (the workspace `direnv exec …` wrapper), and the deduped raw-findings list:
> ```
> <paste the Step-4 deduped findings here>
> ```

Resolve `<this skill's absolute path>` from the skill's announced base directory so the agent can `Read` the contract. The contract itself covers Steps A/B and the three-list output format, so nothing about the anchoring logic needs to be repeated here.

The subagent has already verified claims against source — **do NOT re-add findings it dropped**, and treat its `fix` code as scope-checked (Step 7 styles the prose around it but keeps that code verbatim).

## Step 7 — Attach emoji levels, then write comments in the user's style

For each COMMENT from Step 6, attach its emoji, then write the body.

- **Level → emoji + required vs optional.** The anchor-verifier already normalized every finding to one of four levels — do NOT re-judge severity here. The emoji is for the **chat-facing report only** (Steps 8 & 10) so severities scan at a glance — NEVER put it in the posted PR comment body (the posted body stays emoji-free).

  | Emoji | Level | Gate |
  |-------|-------|------|
  | 🔴 | Critical | Required |
  | 🟠 | Major | Required |
  | 🟡 | Minor | Optional |
  | 🔵 | Optional | Optional |

  Required = 🔴 / 🟠 (must-fix). Optional = 🟡 / 🔵 — mark it in the comment body (e.g. `(optional)`, phrased per your Personalize voice).

- **Write each body in the review voice defined in Personalize** — terse, direct but softened, prefer a question to push back when reconsideration is the point. No emoji in the posted PR comment body.
- **Reference the project's own scripts.** When a fix means running a tool (formatter, linter, codegen), cite the repo's task-runner script (e.g. `yarn format`, `make lint`) — check the repo's scripts first — not the raw binary (`prettier --write`).
- **Body contract — the posted body is exactly these three parts, in this order:**

  ```
  **<summary line>**        ← line 1, bold, always present

  <reasoning>

  <fix block>               ← last, exactly once
  ```

  1. **Summary line — REQUIRED, line 1, bold.** The verifier's one-line problem compressed into a scannable headline, in your voice. GitHub shows only the opening of a comment in the PR timeline, in email notifications, and in the collapsed "Files changed" view — this line has to convey what is wrong on its own, without the reader opening the thread. It is the SAME string you use as this finding's headline at the Step-8 gate: write it once, use it in both places.
  2. **Reasoning** — why it breaks and what it costs, with concrete `file:line` pointers.
  3. **Fix block — last, exactly once.** A GitHub ```suggestion block when `fix_is_replacement: true`: the verifier's `fix` is already the exact full replacement for the anchored range (`start_line`..`line`, indentation included), so paste it verbatim. When `fix_is_replacement: false` (adds code elsewhere, adds a test, a conceptual change), a suggestion block renders a broken "Apply" button — use a plain ``` fence with the corrected example instead. Suggestion blocks are ONLY for verifier-confirmed exact replacements.

  ````
  **`Amount` เก็บเป็น string ทำให้ต้อง parse ทุกที่ที่ใช้**

  ทำไมเก็บ Number เป็น string ครับ ใช้ `int` ตรงๆ ไม่ต้อง parse ทีหลัง
  ```suggestion
  	Amount int `json:"amount"`
  ```
  ````

  **Terminology — do not confuse the two.** This summary *line* lives inside each inline comment body and is required. A PR-level summary *comment* is a separate object, and stays forbidden throughout.

## Step 8 — Selection gate (user replies with the numbers to post)

Build the planned comments but DO NOT post yet.

**The gate is ONE plain-text message that ends your turn.** No tool call carries it: not AskUserQuestion (its checkbox UI truncates finding details — explicitly rejected by the user), not ExitPlanMode, not a yes/no confirm. The message has exactly this shape, in this order:

1. **Anchorable findings, grouped by severity level, numbered continuously across groups** (🔴 first; omit an empty group). Every item carries its detail and its code pointer inline, plus the exact comment body that would be posted (the Step 7 voice + suggestion block):

   The item's headline and the body's first line are the same summary string — that repetition is expected. **Never strip the summary line out of the body to make the gate look less redundant**: the gate is a preview, and the body is what the PR author actually reads.

   ```
   🔴 Critical Issue
   1.) <summary line> — `file:line`
       > **<summary line>**
       >
       > <reasoning>
       > <fix block>

   🟠 Major Issue
   2.) <summary line> — `file:line`
       > **<summary line>**
       >
       > <reasoning>
       > <fix block>

   🟡 Minor Issue
   3.) ...

   🔵 Optional
   4.) ...
   ```

2. **Un-anchorable findings** (from Step 6): same severity-emoji grouping, but clearly headed "not postable — report only" and NOT numbered into the selection list. Below them, list the verifier's DROPPED items (claim false/unconfirmable) in one line each — the user may know context the verifier couldn't see — and any `CUT: <n>` counts the Step-4 agents reported, in one line, so the user can ask for a deeper pass.

3. **Closing ask** — one line asking which numbers to post, accepting numbers/ranges/all/none, and recommending the 🔴/🟠 ones — phrased in your Personalize voice. e.g. `เลือกหมายเลขที่จะให้ post ได้เลยครับ (เช่น "1 3 4", "1-3", "all", "none") — แนะนำ 1-2 (🔴/🟠)`

Then **end your turn and wait for the reply**. Parse it (numbers, ranges, `all`, `none`, or natural-language phrasing like "all except 3" / "ทั้งหมดยกเว้นข้อ 3") and post ONLY the selected numbers (Step 9). Unselected anchorable findings are not dropped silently: recap them in the Step 10 report as available-but-not-posted, alongside the un-anchorable ones.

## Step 9 — Post inline comments

**Freshness guard first.** The Step-8 gate can sit for a while; if the author pushed meanwhile, every anchor is stale. Re-check: `gh pr view "$PR" --json headRefOid` — if it no longer equals `HEAD_SHA`, STOP and tell the user the PR head moved (re-run the skill to review the new head); do NOT post against the old SHA.

Post each comment on its own line with the **single-comment endpoint** — this is what guarantees no PR-level summary comment. (The batch `.../reviews` endpoint cannot be used: its `event: COMMENT` requires a non-empty top-level `body`, i.e. exactly the PR-level summary the user does not want.)

Suggestion bodies contain newlines + backticks, so write each comment as JSON to the session scratchpad dir (not `/tmp/claude-*`) and post via `--input` — JSON escaping is reliable, shell backtick pitfalls avoided:

```bash
gh api --method POST -H "Accept: application/vnd.github+json" \
  /repos/{owner}/{repo}/pulls/$PR/comments --input "$COMMENT_JSON"
```

Each `$COMMENT_JSON` file:
```json
{
  "body": "**`Amount` เก็บเป็น string ทำให้ต้อง parse ทุกที่ที่ใช้**\n\nทำไมเก็บ Number เป็น string ครับ ใช้ `int` ตรงๆ ไม่ต้อง parse ทีหลัง\n```suggestion\n\tAmount int `json:\"amount\"`\n```",
  "commit_id": "<HEAD_SHA>",
  "path": "src/x.go",
  "line": 42,
  "side": "RIGHT"
}
```

- `line` = RIGHT-side line number in the head file. When the verifier returned `start_line` (multi-line finding): add `"start_line": <it>, "start_side": "RIGHT"` (`line` stays the last line). Deleted-code comments use `"side": "LEFT"`.
- Loop one call per **user-selected** comment (from the Step 8 gate). If a call 422s, that line is not in a diff hunk — drop it (move to Step 10's report), don't retry as-is.
- `{owner}/{repo}` auto-fill from the current repo, or set `GH_REPO=owner/repo`.

## Step 10 — Report

Tell the user: N inline comments posted (with the PR URL), each recapped with its severity emoji (🔴 / 🟠 / 🟡 / 🔵 — from Step 7), and print the findings that were NOT posted — the un-anchorable ones, any anchorable findings the user chose not to select at the Step 8 gate (severity emoji + note), the verifier's DROPPED list (one line each), and any Step-4 `CUT: <n>` counts — so nothing is silently dropped. Order both lists by severity (🔴 first). If the review found nothing, say so plainly (no emoji needed).
