# Claude Code

```sh
../install.sh claude      # -> ~/.claude/skills/octaweave
```

A symlink, not a copy, so `git pull` updates it. Restart Claude Code afterwards so skill
discovery runs again.

`skills/octaweave/SKILL.md` is the operating procedure — when to reach for Octaweave, the
`whoami`-first rule, and the writes that need care. `skills/octaweave/reference/api.md` is
a symlink to the repo's [`API.md`](../API.md) and holds the full endpoint reference; the
skill tells Claude to read it before the first write of a session, which is what keeps the
always-loaded part short.

To scope it to one project instead of every session, symlink into `.claude/skills/` inside
that repo.

Set the key before use:

```sh
export OCTAWEAVE_API_KEY=owk_live_…
```
