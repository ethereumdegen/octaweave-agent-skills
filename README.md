# Octaweave agent skills

Give your agents a workspace — and then tell them how to use it.

[Octaweave](https://octaweave.com) is notes, a kanban board, a drive, a calendar, a blog,
and an image studio: a suite a person works in every day, and a single bearer token that
lets their agents work in it too. Same objects, same permissions, same live updates.

This repo is the instruction half. Four agents, four packaging formats, one API.

| folder | for | install |
|---|---|---|
| [`claude/`](claude) | Claude Code | `./install.sh claude` |
| [`codex/`](codex) | OpenAI Codex | `./install.sh codex` |
| [`omp/`](omp) | [OMP](https://omp.sh) | `./install.sh` |
| [`metalcraft-agent/`](metalcraft-agent) | [Metalcraft Agent](https://metalcraftai.com) | `install_pack octaweave` |

[**`API.md`**](API.md) is the canonical endpoint reference underneath all four — the
whole surface, the error codes, and the handful of rules that decide whether an agent is
safe to let loose in someone's workspace. The Claude and OMP skills symlink it; the Codex
instructions inline what matters and point at it; the Metalcraft pack turns it into 32
typed tools.

## Get a key

Sign in at [octaweave.com](https://octaweave.com), open a workspace, and go to
**Keys → Create**. Then:

```bash
export OCTAWEAVE_API_KEY=owk_live_…
```

Two things worth knowing before you hand it to anything:

- **A key is pinned to exactly one workspace.** There is no org-wide key — that would be
  a single credential reading every workspace in the org, which is precisely the blast
  radius worth not having. `whoami` tells an agent which workspace it is in.
- **A key can never mint another key.** The endpoint refuses any request authenticated by
  a key, so a leaked read-only key cannot escalate itself.

Scope it down while you're there: `notes:read` if the job is reading notes. The modules
are `notes`, `blog`, `board`, `drive`, `calendar`, `search`, and `studio`; the actions are
`read`, `write`, and `publish`.

## Try it

```bash
curl -s https://octaweave.com/api/v1/whoami -H "Authorization: Bearer $OCTAWEAVE_API_KEY"
```

```json
{ "actor": { "type": "api_key", "label": "deploy-bot", "workspace_id": "9f2c…" }, … }
```

That `workspace_id` is the `{ws}` in every other path.

```bash
curl -X POST https://octaweave.com/api/v1/w/$WS/notes \
  -H "Authorization: Bearer $OCTAWEAVE_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"title":"Q3 teardown","body":"## Findings\n- …","labels":["research"]}'
```

## What these skills actually teach

Anyone can paste an endpoint list. The part worth packaging is the handful of rules that
separate an agent that helps from one that quietly wrecks a workspace:

- **`base_version` on every edit.** Read the object, keep its `version`, send it back.
  A mismatch returns `409 stale_write` with the current object attached to merge against.
  Skip it and you get last-write-wins, which deletes a human's paragraph with no trace.
- **Trash instead of delete.** Deleting a drive file that a published post displays
  breaks that post for every reader while looking fine to the author — they're signed in.
- **Cards move relative to a sibling, never by index.** `after` absent, `null`, or an id
  are three different instructions.
- **Editing a repeating event has to pick a scope.** `this` or `all`, and guessing is how
  people lose meetings.
- **Studio spends real credits**, including on generations the provider's content filter
  blocks. Idempotency keys are not optional.

Each format states these in the way its agent will actually read them.

## Self-hosting

Octaweave is one Rust binary and is
[MIT licensed](https://github.com/ethereumdegen/octaweave-spaces). If you run your own,
swap the host: the skills default to `https://octaweave.com` and nothing else changes.
The Metalcraft pack hardcodes the origin in each tool URL, so edit
`metalcraft-agent/packs/octaweave/api_tools/*.json` before publishing it to your registry.

## License

MIT. See [LICENSE](LICENSE).
