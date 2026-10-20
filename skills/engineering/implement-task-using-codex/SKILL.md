---
name: implement-task-using-codex
description: implement-task with Codex (moonsmith) writing the code and you as planner, reviewer and committer.
disable-model-invocation: true
---

# implement-task-using-codex

Run the **`implement-task`** skill exactly as written, with one change: the implementer is
**moonsmith**, not a Claude subagent. moonsmith is Codex (`gpt-6-luna`, effort `xhigh`, write
mode) driven through the official `codex@openai-codex` plugin. You stay the controller: you plan,
you check every diff, you run the tests, and you write every commit.

Invoke `implement-task` now and follow its phases. Wherever it dispatches an implementer
(Phase 3 tasks, Phase 4 doc updates, Phase 6 step 4.1 substantive fixes), dispatch moonsmith with
the loop below. Every task goes to moonsmith, including a single small task: Phase 3's
"implement directly yourself" exception does not apply. A small mechanical review fix in Phase 6
you may still apply directly.

## Preflight (once, before Phase 3)

```bash
COMPANION=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | sort -V | tail -1)
node "$COMPANION" setup --json
```

Done when `setup` reports Codex installed and authenticated. If the plugin is missing, Codex is
not ready, or a later run fails on a usage limit, **stop and ask the user**: wait for the quota,
or run this task with `implement-task`'s normal implementer. Never switch implementers silently.

## moonsmith loop (per plan task)

1. **Brief.** Write the brief to a file in your scratchpad (outside the worktree):
   - the plan's task section, verbatim, plus the spec and plan paths;
   - the worktree path `$WT`, and "follow `AGENTS.md` / `CLAUDE.md` and sibling-file style";
   - test first: write the failing test, run it, see it fail, then write the code;
   - run only the focused unit tests for the touched packages; skip integration and e2e
     (Docker and ports are yours);
   - edit files only — leave git and GitHub to the controller: no commit, stage, branch,
     stash or push, and no `gh`;
   - finish with: files changed, tests added, test commands and their results, open questions.
2. **Dispatch** with Bash `run_in_background: true` (a run can take many minutes; wait for the
   completion notice, do not poll):
   ```bash
   node "$COMPANION" task --write --fresh --model gpt-6-luna --effort xhigh \
     --cwd "$WT" --prompt-file "<brief file>"
   ```
3. **Check** the returned work in `$WT`:
   - `git status --porcelain` (new files are untracked, so plain `git diff` misses them),
     then `git diff` against the task's requirement and test matrix;
   - `HEAD` is unchanged since dispatch (moonsmith committed nothing);
   - re-run the focused tests yourself. moonsmith's reported results are a claim, not evidence.
4. **Fix round** when the approach is wrong, a case is missing, or tests are thin: write the
   findings to a new brief and dispatch with `--resume-last` instead of `--fresh` (the thread is
   kept per worktree, so moonsmith keeps its context). After 3 fix rounds on one task, stop and
   take the finding history to the user.
5. **Commit** when the check passes: stage the files by name (production and tests together) and
   commit with the repo's message convention, following `implement-task`'s hard rules.

Done when every plan task is committed this way. Then continue `implement-task` from Phase 4.
