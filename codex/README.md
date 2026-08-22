# OpenAI Codex

Codex has no skill discovery — it reads `AGENTS.md` from the project it's working in — so
the instructions here are written to be complete on their own rather than progressively
loaded.

**Per project:**

```sh
cat AGENTS.md >> /path/to/your/project/AGENTS.md
```

**Everywhere**, by appending the same content to `~/.codex/AGENTS.md`.

**As a slash command:**

```sh
../install.sh codex       # -> ~/.codex/prompts/octaweave.md
```

`/octaweave <what you want done>` then runs the procedure in `prompts/octaweave.md`.

[`AGENTS.md`](AGENTS.md) carries the working set inline — credentials, the `whoami`-first
rule, the three rules that matter, and a condensed endpoint reference. `API.md` here is a
symlink to the repo's [full reference](../API.md); `AGENTS.md` points Codex at it for
anything it doesn't cover.

Set the key before use:

```sh
export OCTAWEAVE_API_KEY=owk_live_…
```
