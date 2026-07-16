---
name: pr-review-inline
description: >
  Use when the user wants a GitHub Pull Request reviewed with findings posted
  as inline, line-level comments on the changed code (NOT a summary comment).
  Triggers on /pr-review-inline, "review this PR and comment", "รีวิว PR แล้ว
  คอมเมนต์ในโค้ด", or a PR number/URL given for review.
argument-hint: "[PR number or URL]"
---

# /pr-review-inline

Review a GitHub PR with `/pr-review-toolkit:review-pr`, then post each finding as an **inline line comment** (with a fix suggestion) on the exact problematic line. No summary comment — only line comments.

Follow every step in order. Do not skip guards. Posting to a PR is outward-facing — never post without the per-issue selection gate in Step 8, and post only the findings the user selects there.

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

- If yes: **dispatch the `task-source-resolver` template as an `Explore` agent (model `sonnet`) in the background**, then continue to Step 3 immediately — the Jira fetch and the bridge are independent; **join before Step 4** (the only step that needs the ticket). The Jira payload (description + comment thread) never enters the main context — only the resolver's distilled block does. Dispatch prompt:
  > Read `<implement-task skill dir>/agents/task-source-resolver.md` (the `implement-task` skill directory, sibling of this skill's) and follow it EXACTLY. Input: Jira `<KEY>`. Call `getJiraIssue` with `cloudId` = `<jira-site>` directly (no `getAccessibleAtlassianResources`).

  On join, apply these caller rules:
  - `NOTES` reports fetch failure / MCP tools missing → **STOP the skill**: tear down the worktree (Step 5 command) and tell the user to run `/reload-plugins` (MCP tools register only at session start — enabling/authing mid-session alone won't surface them) and re-run. Do NOT fall back to WebFetch (`<jira-site>` is private and WebFetch fails on it) or to pasting; do NOT continue the review without the ticket.
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

Then **dispatch the applicable agents yourself via the Agent tool (in parallel)**, scaling the count to the PR's size/risk to save tokens (agents are ~90% of this skill's cost):

- **Tiny** — ≤2 changed code files AND ≤~80 changed lines AND no risky path (auth, money/payment, SQL/migrations, crypto, concurrency): dispatch **`code-reviewer` only** (+ `pr-test-analyzer` iff test files changed). Do NOT fan out.
- **Medium** (default): `code-reviewer` + the agents whose aspect actually changed, per review-pr's aspect→agent map (tests→pr-test-analyzer, comments/docs→comment-analyzer, error handling→silent-failure-hunter, new types→type-design-analyzer).
- **Large / risky** (many files, large diff, or touches a risky path): the full applicable set.
- Never dispatch `simplify` / `code-simplifier` — it MUTATES code. If review-pr lists an agent not in the fallback below, still consider it (that's why we read its output).

Fallback roster if review-pr's output is unavailable: `code-reviewer` (always), `pr-test-analyzer` (tests), `comment-analyzer` (comments/docs), `silent-failure-hunter` (error handling), `type-design-analyzer` (new types). **Dispatch with the full `subagent_type`** — these agents live under the plugin namespace, e.g. `pr-review-toolkit:code-reviewer`; the short name alone fails.

**Model per agent** (override via the Agent tool; default inherits the session model):
- `code-reviewer`, `silent-failure-hunter` → keep the session model — correctness-critical, do NOT downgrade.
- `pr-test-analyzer`, `type-design-analyzer` → `sonnet`.
- `comment-analyzer` → `haiku`.

Each agent prompt MUST include: the repo + PR intent + the Step-2 Jira context (TITLE / DESCRIPTION / COMMENTS, if fetched); the **worktree cwd** and that `git diff` there shows exactly the PR's changes; an instruction to read the changed files in full. **Require terse output** — return ONLY actionable findings as a compact list, each `{severity, file, NEW-file line (RIGHT side), one-line problem, one-line fix}`; NO positives, NO "not a defect / confirmed safe" notes, NO narration of how the review was done; cap ~8 findings ordered by severity; end with "your final message IS the data I consume — return the findings list directly." (The agent still reasons fully — only its final message must be terse; its reasoning never enters your context anyway.) Collect every agent's output and dedupe across them (findings on the same file:line often overlap). **This deduped raw-findings list is the ONLY input the Step 6 anchor-verifier needs from the review** — the raw diff itself never has to enter your context.

## Step 5 — Tear down the worktree

Posting uses the PR head SHA + file paths and does not depend on local git state, so clean up now:

```bash
cd "$ROOT"
git worktree remove --force "$ROOT.worktrees/review-pr-$PR"   # use-worktree layout — byte-identical to Step 3's WT; --force: worktree holds the dirty reset state
```

No branch to delete — the worktree was detached. The user's checkout was never modified. The sibling path here **must match Step 3's `WT` exactly** (`$WT` does not survive across shell calls); if it drifts, the stale worktree survives and breaks the next review of this PR with "already exists".

## Step 6 — Anchor & verify findings (dispatch the anchor-verifier subagent)

The raw findings from Step 4 are unverified and unanchored. Building the commentable line-set (parsing the full `gh pr diff`) and verifying each finding against the head file are **token-heavy, mechanical, self-contained** work — so push them into ONE dedicated subagent instead of doing them in the main context. The subagent absorbs the raw diff + head files; you get back only three small structured lists (COMMENTS / UN-ANCHORABLE / DROPPED). **This is the context firewall that keeps the raw diff (often tens of KB) out of the main thread** where it would otherwise persist through the rest of the run.

**Dispatch ONE agent via the Agent tool** — `general-purpose`, **keep the session model** (verification of Critical claims is correctness-critical; do NOT downgrade). It runs AFTER teardown (Step 5), so the worktree is gone — it must read source via `git show "$HEAD_SHA":<path>` (works with no checkout), NOT worktree files. **It posts nothing — its final message returns data.**

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
- **Fix format = GitHub ```suggestion block** (user's choice) when the finding has `fix_is_replacement: true`. The verifier's `fix` is already the exact full replacement for the anchored range (`start_line`..`line`, indentation included) — paste it verbatim:
  ````
  ใช้ int ดีกว่าครับ ไม่ต้อง parse ทีหลัง
  ```suggestion
  	Amount int `json:"amount"`
  ```
  ````
  When `fix_is_replacement: false` (add code elsewhere, add a test, a conceptual change), a suggestion block can't express it — use a **plain ``` fence** with the corrected example instead.

## Step 8 — Selection gate (user replies with the numbers to post)

Build the planned comments but DO NOT post yet.

**The gate is ONE plain-text message that ends your turn.** No tool call carries it: not AskUserQuestion (its checkbox UI truncates finding details — explicitly rejected by the user), not ExitPlanMode, not a yes/no confirm. The message has exactly this shape, in this order:

1. **Anchorable findings, grouped by severity level, numbered continuously across groups** (🔴 first; omit an empty group). Every item carries its detail and its code pointer inline, plus the exact comment body that would be posted (the Step 7 voice + suggestion block):

   ```
   🔴 Critical Issue
   1.) <one-line problem> — `file:line`
       > <planned comment body>

   🟠 Major Issue
   2.) <one-line problem> — `file:line`
       > <planned comment body>

   🟡 Minor Issue
   3.) ...

   🔵 Optional
   4.) ...
   ```

2. **Un-anchorable findings** (from Step 6): same severity-emoji grouping, but clearly headed "not postable — report only" and NOT numbered into the selection list. Below them, list the verifier's DROPPED items (claim false/unconfirmable) in one line each — the user may know context the verifier couldn't see.

3. **Closing ask** — one line asking which numbers to post, accepting numbers/ranges/all/none, and recommending the 🔴/🟠 ones — phrased in your Personalize voice. e.g. `เลือกหมายเลขที่จะให้ post ได้เลยครับ (เช่น "1 3 4", "1-3", "all", "none") — แนะนำ 1-2 (🔴/🟠)`

Then **end your turn and wait for the reply**. Parse it (numbers, ranges, `all`, `none`, or natural-language phrasing like "all except 3" / "ทั้งหมดยกเว้นข้อ 3") and post ONLY the selected numbers (Step 9). Unselected anchorable findings are not dropped silently: recap them in the Step 10 report as available-but-not-posted, alongside the un-anchorable ones.

## Step 9 — Post inline comments

**Freshness guard first.** The Step-8 gate can sit for a while; if the author pushed meanwhile, every anchor is stale. Re-check: `gh pr view "$PR" --json headRefOid` — if it no longer equals `HEAD_SHA`, STOP and tell the user the PR head moved (re-run the skill to review the new head); do NOT post against the old SHA.

Post each comment on its own line with the **single-comment endpoint** — this guarantees **no summary**. (Do NOT use the batch `.../reviews` endpoint: `event: COMMENT` there requires a non-empty top-level `body`, which is a summary the user does not want.)

Suggestion bodies contain newlines + backticks, so write each comment as JSON to the session scratchpad dir (not `/tmp/claude-*`) and post via `--input` — JSON escaping is reliable, shell backtick pitfalls avoided:

```bash
gh api --method POST -H "Accept: application/vnd.github+json" \
  /repos/{owner}/{repo}/pulls/$PR/comments --input "$COMMENT_JSON"
```

Each `$COMMENT_JSON` file:
```json
{
  "body": "ใช้ int ครับ ไม่ต้อง parse ทีหลัง\n```suggestion\n\tAmount int `json:\"amount\"`\n```",
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

Tell the user: N inline comments posted (with the PR URL), each recapped with its severity emoji (🔴 / 🟠 / 🟡 / 🔵 — from Step 7), and print the findings that were NOT posted — the un-anchorable ones, any anchorable findings the user chose not to select at the Step 8 gate (severity emoji + note), and the verifier's DROPPED list (one line each) — so nothing is silently dropped. Order both lists by severity (🔴 first). If the review found nothing, say so plainly (no emoji needed).

## Quick reference

| Need | Command |
|------|---------|
| PR metadata | `gh pr view "$PR" --json number,title,body,headRefOid,baseRefName,url` |
| Diff (anchor-verifier builds the line-set from this) | `gh pr diff "$PR"` |
| Head SHA (commit_id) | `gh pr view "$PR" --json headRefOid -q .headRefOid` |
| Read head file (post-teardown, no checkout) | `git show "$HEAD_SHA":<path>` |
| Post inline comment | `gh api --method POST .../pulls/$PR/comments --input comment.json` |
| Edit a posted comment | `gh api --method PATCH .../pulls/comments/{comment_id} --input comment.json` |

## Common mistakes

- **Posting a line not in the diff → 422.** Always gate on the line-set the Step-6 anchor-verifier builds; never post a finding it moved to the un-anchorable list.
- **Building the line-set / verifying in the main context** → the raw `gh pr diff` (tens of KB) and head files then persist in main through the rest of the run. Push that work into the Step-6 subagent; main should only ever see its three returned lists.
- **Bridging in-place, or nesting the worktree inside the repo** → rewrites the user's working tree / pollutes its `git status`. Always a **sibling** worktree outside `$ROOT` (Step 3); tear it down in Step 5.
- **Skipping `git add -N .` after the reset** → files the PR ADDED are untracked, `git diff` hides them, and the review silently misses whole files (a pure-addition PR even reads as an empty diff). The intent-to-add line in Step 3 is load-bearing.
- **Anchor-verifier reading worktree files** → they're gone after Step 5. It must use `git show "$HEAD_SHA":<path>`.
- **Forcing a whole-file / missing-test / type-level note onto a diff line** → it belongs on the un-anchorable list (Step 6), printed in the terminal (Step 10), never posted.
- **Gating with AskUserQuestion, ExitPlanMode, or an all-or-nothing yes/no** → AskUserQuestion's checkbox UI truncates finding details (explicitly rejected by the user); yes/no can't drop individual nits. Step 8 MUST be the severity-grouped, continuously numbered plain-text list, answered by the user's reply with numbers.
- **Keeping an unverified Critical** → the anchor-verifier must confirm high-severity claims against source and drop/downgrade what it can't. Never post an unverified critical.
- **Empty `git diff` after the bridge** → `review-pr` reviews nothing; fail loud, don't post "no issues".
- **Including `simplify`** → mutates code. Never pass it.
- **`suggestion` block on a `fix_is_replacement: false` finding** → renders a broken "Apply" button. Suggestion blocks ONLY for verifier-confirmed exact replacements; plain fence otherwise.
- **Posting against a stale `HEAD_SHA`** → the author pushed while the Step-8 gate waited; anchors go outdated or 422. Re-check `headRefOid` before posting (Step 9).
- **Posting a summary comment** → not wanted. Use the single-comment endpoint (per line); never the batch `reviews` endpoint (its COMMENT event forces a summary body).
- **Expecting `review-pr` to return findings** → it returns a workflow only. You must dispatch the specialist agents yourself (Step 4).
- **Working around a missing repo / down Jira MCP** → don't. Fail fast: repo not found or wrong repo → stop (Step 1); Jira requested but MCP unreachable → stop and tell the user to `/reload-plugins` (Step 2).
