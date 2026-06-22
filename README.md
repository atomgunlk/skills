# atomgun-skills

Personal Claude skills.

## Skills

| Skill | Trigger | Purpose |
| ----- | ------- | ------- |
| [fix-pr-mantra](skills/engineering/fix-pr-mantra/SKILL.md) | `/fix-pr-mantra` | Triage PR review comments — gather, decide fix/won't-fix, confirm before editing, then close the loop. |

## Install

The skills are registered via `.claude-plugin/plugin.json`.

**Claude Code** — symlink into the runtime skills dir (stays in sync with the source):

```sh
ln -s "$PWD/skills/engineering/fix-pr-mantra" ~/.claude/skills/fix-pr-mantra
```

**Kiro** — hard copy into its skills dir (re-run after editing the source to re-sync):

```sh
cp -R "$PWD/skills/engineering/fix-pr-mantra" ~/.kiro/skills/fix-pr-mantra
```
