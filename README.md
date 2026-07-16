# atomgun-skills

Battle-tested [agent skills](https://agentskills.io) for real engineering workflows — git worktree discipline, end-to-end task implementation, PR review/fix loops, and the sharp edges of editing Jira/Confluence through an agent.

Every skill is a plain `SKILL.md` (+ optional `scripts/` and agent-prompt templates), so they work with any skill-aware runtime: Claude Code, Kiro, or any agent that can read a markdown file and run shell commands. Paths inside each skill are written relative to the skill's own directory — no hardcoded home paths.

## Skills

| Skill | Use when | Bundled |
|---|---|---|
| [use-worktree](skills/engineering/use-worktree/SKILL.md) | Creating git worktrees — sibling layout, safe teardown, stale-registration cleanup | `create-worktree.sh` |
| [implement-task](skills/engineering/implement-task/SKILL.md) | Implementing a task end-to-end: Jira/plan/prompt → brainstorm → TDD in a worktree → review-fix loop → PR | 2 read-only agent templates |
| [pr-review-inline](skills/engineering/pr-review-inline/SKILL.md) | Reviewing a GitHub PR and posting findings as inline line comments (never a summary) with a per-finding selection gate | anchor-verifier contract |
| [fix-pr-mantra](skills/engineering/fix-pr-mantra/SKILL.md) | Addressing PR review comments — every comment gets a verdict, nothing is edited before the plan is approved | ledger-builder contract |
| [jira-writing](skills/engineering/jira-writing/SKILL.md) | Creating/editing Jira issues via the Atlassian MCP — ADF vs markdown traps, smartlink chips, EARS acceptance criteria | — |
| [confluence-writing](skills/engineering/confluence-writing/SKILL.md) | Updating Confluence pages via the Atlassian MCP — whole-body replace hazards, WAF blocks, huge pages | — |

The six skills compose: `implement-task` drives `use-worktree` for isolation and a review loop before its PR; `fix-pr-mantra` closes the loop after review; `pr-review-inline` is the reviewer's side of the same table.

> **Dependencies:** `pr-review-inline` and `implement-task` require `use-worktree` (its bundled script does all worktree creation), and `pr-review-inline` also reads an agent template from `implement-task`. The plugin install brings all six; for manual installs, install those together.

## Install

### Claude Code (plugin)

```
/plugin marketplace add atomgunlk/skills
/plugin install atomgun
```

### Claude Code (manual, stays in sync with your clone)

```sh
git clone https://github.com/atomgunlk/skills.git
cd skills
ln -s "$PWD/skills/engineering/<skill-name>" ~/.claude/skills/<skill-name>
```

### Kiro

```sh
cp -R skills/engineering/<skill-name> ~/.kiro/skills/<skill-name>
```

### Codex / Cursor / other agents

Copy the skill directory anywhere your agent can read, and reference it from your instructions file (`AGENTS.md`, rules, etc.):

```markdown
When working with git worktrees, read and follow <path>/use-worktree/SKILL.md.
```

Scripts resolve relative to the skill directory, so any location works.

## Personalize

Skills that touch company systems (`pr-review-inline`, and the Atlassian pair) start with a **`## Personalize`** section — a small table of placeholders (your Jira site, ticket-key regex, `gh` wrapper, review voice) with the author's real setup shown as a worked example. Replace the example column with your values before first use; everything else is generic.

## How these were built

Each skill came out of real production use, then a verification pass: shell scripts are live-tested (contract: result on stdout, diagnostics on stderr), inter-file contracts are cross-checked, and MCP parameter names are validated against live tool schemas. The authoring approach follows the TDD-for-documentation methodology from [obra/superpowers](https://github.com/obra/superpowers) (`writing-skills`).

## License

[MIT](LICENSE)
