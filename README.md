# atomgun-skills

Personal Claude skills.

## Skills

| Skill | Trigger | Purpose |
| ----- | ------- | ------- |
| [fix-pr-mantra](skills/engineering/fix-pr-mantra/SKILL.md) | `/fix-pr-mantra` | Triage PR review comments — gather, decide fix/won't-fix, confirm before editing, then close the loop. |

## Install

The skills are registered via `.claude-plugin/plugin.json`. To activate a skill
directly, symlink it into your runtime skills directory:

```sh
ln -s "$PWD/skills/engineering/fix-pr-mantra" ~/.claude/skills/fix-pr-mantra
```
