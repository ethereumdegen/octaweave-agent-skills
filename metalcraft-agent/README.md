# Metalcraft Agent

An integration **pack** in the [metalcraft-agent](https://github.com/ethereumdegen/metalcraft-agent)
format: a manifest, declarative HTTP tools, a persona, and a skill. This is the richest of
the four formats — the agent gets 32 typed, individually-described tools rather than a
prose description of a REST API, so a wrong call is usually a schema error instead of a
404.

```
packs/octaweave/
  pack.json                        manifest — id, description, requires_env
  api_tools/*.json                 32 declarative HTTP tools
  personas/octaweave-agent.json    the persona that binds them together
  skills/octaweave-workspace.md    the how, loaded on demand via load_skill
```

## Install

Packs are installed from the registry at `packs.metalcraftai.com`:

```
install_pack octaweave
```

Then set the credential the manifest declares:

```sh
export OCTAWEAVE_API_KEY=owk_live_…
```

Every tool carries `Authorization: Bearer $OCTAWEAVE_API_KEY` in its headers, resolved
through the agent's key store first and the process environment second — so a managed key
and a `.env` value both work, and the model never sees the token.

## Publish

This repo is the source of truth for the pack. To push it to a registry, use the
`seed-to-registry.sh` script from
[metalcraft-agent-external-packs](https://github.com/ethereumdegen/metalcraft-agent-external-packs):

```sh
python3 /path/to/metalcraft-agent-external-packs/scripts/validate-packs.py packs
MCK_ADMIN_PAT=mck_… /path/to/metalcraft-agent-external-packs/scripts/seed-to-registry.sh \
  --pack octaweave
```

Run the validator after any edit — it checks the manifest, that every tool file is
self-named, and that the persona only references tools and skills that exist.

## The one thing the tools can't do

Uploading a file is three steps and the middle one is a raw `PUT` to a presigned object
storage URL, which a declarative HTTP tool can't express. So the persona lists the native
`bash` tool alongside the pack, and the flow is:

1. `octaweave_presign_upload` → `{upload_id, url}`
2. `curl -X PUT --upload-file <path> -H 'content-type: <type>' "<url>"` via `bash`
3. `octaweave_confirm_upload` → the file row

`skills/octaweave-workspace.md` spells this out, along with the `base_version` rule, the
relative card ordering, the recurring-event scope, and the error codes.

## Self-hosting Octaweave

Tool URLs hardcode `https://octaweave.com`, matching how the other external packs handle
their origins. Point them somewhere else with:

```sh
sed -i '' 's|https://octaweave.com|https://your-host|g' packs/octaweave/api_tools/*.json
```
