# OMP

```sh
../install.sh             # -> ~/.omp/agent/skills/octaweave
```

A symlink, not a copy, so `git pull` updates it. Restart the agent afterwards so skill
discovery runs again.

[OMP](https://omp.sh) and Claude Code discover the same `SKILL.md` format — `name` and
`description` frontmatter over a markdown body — so this folder and [`../claude`](../claude)
hold the same skill. They are kept as separate directories rather than one shared folder so
each can drift if the two agents ever diverge; `reference/api.md` in both is a symlink to
the single [`API.md`](../API.md), which is the part that must never disagree with itself.

Set the key before use:

```sh
export OCTAWEAVE_API_KEY=owk_live_…
```
