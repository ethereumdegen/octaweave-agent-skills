# The Octaweave API, for agents

Octaweave is a workspace — notes, a kanban board, a drive, a calendar, a blog, and an
image studio — that a person uses in a browser and an agent uses over HTTP. Same
objects, same permissions, same live updates. This document is the whole surface an
agent needs.

Base URL: **`https://octaweave.com`**, everything under **`/api/v1`**.
Self-hosted deployments use their own host; only the origin changes.

---

## 1. Authenticating

One header, on every request:

```
Authorization: Bearer owk_live_7f3a…
```

Keys are minted in the workspace UI (**Keys**) or by a signed-in human calling
`POST /api/v1/w/{ws}/keys`. Two facts about them that decide how you write code:

- **A key belongs to exactly one workspace.** There is no org-wide key. Calling
  `/w/{other}` with it returns `403 forbidden` no matter what the key's scopes say.
- **A key can never mint another key.** `POST /w/{ws}/keys` refuses any request
  authenticated by a key (`403`), so a leaked read-only key cannot escalate itself.

Tokens are `owk_live_…` in production and `owk_test_…` on a deployment with
`SECURE_COOKIES=false` (i.e. local dev). The full token is returned **once**, at
creation; only its hash is stored.

### Find out what you are

```bash
curl -s https://octaweave.com/api/v1/whoami \
  -H "Authorization: Bearer $OCTAWEAVE_API_KEY"
```

```json
{
  "user":   { "id": "…", "handle": "amazzola", "email": "…", "name": "…" },
  "actor":  { "type": "api_key", "label": "deploy-bot", "workspace_id": "9f2c…" },
  "scopes": 2,
  "is_admin": false
}
```

`actor.workspace_id` is the workspace your key is pinned to — **call this first and use
that value as `{ws}`** rather than guessing a slug. `scopes` is a count, not a list;
`null` there means a browser session, which is unrestricted. `is_admin` is always
`false` for a key, deliberately: the admin surface refuses API keys outright, so a key
handed to an agent is never a site administrator even when an administrator created it.

### Scopes

A key carries a list of scopes. Two shorthands and a per-module form:

| scope | grants |
|---|---|
| `read` | read everything in the workspace |
| `write` | read and write everything in the workspace |
| `notes:read` | read the notes module only |
| `notes:write` | read + write the notes module |
| `blog:publish` | publish and unpublish posts |
| `*:write` | same as `write` |

Modules: `notes`, `blog`, `board`, `drive`, `calendar`, `search`, `studio`.
Actions: `read`, `write`, `publish`.

A scope names one module and does not leak into another: `notes:write` cannot touch the
drive. Ask for the narrowest set that does the job — `studio:write` is the one that
spends money.

---

## 2. Shapes you can rely on

**Lists** come back as `{"items": [...]}`. Notes and posts add `"next_cursor"`, which
is `null` on the last page; pass it back as `?cursor=`.

**Errors** are always this object, whatever the status:

```json
{ "error": "a sentence a human can read", "code": "machine_code" }
```

| status | `code` | means |
|---|---|---|
| 400 | `bad_request` | the request was malformed — the sentence says how |
| 401 | `unauthorized` | missing, revoked, or expired key |
| 403 | `forbidden` | the key is scoped out of this, or pinned to another workspace |
| 404 | `not_found` | no such object *in this workspace* |
| 409 | `conflict` | a real collision (duplicate slug, WIP limit) |
| 409 | `stale_write` | you wrote against an old `version` — see below |
| 402 | `payment_required` | out of credits (studio) |
| 429 | `rate_limited` | 600 requests/minute per key |
| 503 | `not_configured` | that module is disabled on this deployment |
| 503 | `database_unavailable` | transient; retry with backoff |
| 502 | `upstream_error` | a provider we call failed |

### Optimistic concurrency — read this before writing

Notes, posts, cards, and events carry a `version`. Send the version you loaded as
`base_version` on a `PATCH`. If someone edited in between, the write is **rejected**
with `409 stale_write` and the response carries the current object under `"current"`:

```json
{
  "error": "the note changed since you loaded it",
  "code": "stale_write",
  "current": { "id": "…", "version": 7, "body": "…", … }
}
```

Merge against `current` and retry with `base_version: 7`. Omitting `base_version`
entirely means last-write-wins — you will silently destroy a human's edit, so only do
it for objects you alone own.

### Realtime

`GET wss://octaweave.com/live?workspace={ws}&since={change_seq}` is a **WebSocket**, not
SSE. Authorization happens before the upgrade and the socket is scoped to that one
workspace for its life. Pass the last `change_seq` you saw as `since` to replay what you
missed; omit it on a fresh connect. Most agents do not need this — poll or just write.

---

## 3. Notes

Markdown is the source of truth. `[[wiki-links]]` between notes are resolved by slug,
and the server tracks backlinks and links to notes that don't exist yet.

| method | path | notes |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/notes` | `?label=`, `?sort=updated\|accessed`, `?limit=`, `?cursor=` |
| `POST` | `/api/v1/w/{ws}/notes` | `{title?, body?, slug?, labels?}` |
| `GET` | `/api/v1/w/{ws}/notes/{note}` | `{note}` is an id **or** a slug |
| `PATCH` | `/api/v1/w/{ws}/notes/{note}` | `{base_version?, title?, body?, slug?, labels?}` |
| `DELETE` | `/api/v1/w/{ws}/notes/{note}` | |

`GET` one note returns the summary fields plus `body` (markdown), `html`
(server-rendered and sanitized — a convenience for readers, never the storage form),
`backlinks`, and `broken_links` (slugs this note links to that don't exist yet).

```bash
curl -X POST https://octaweave.com/api/v1/w/engineering/notes \
  -H "Authorization: Bearer $OCTAWEAVE_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"title":"Q3 teardown","body":"## Findings\n- …","labels":["research"]}'
```

```json
{ "id": "9f2c…", "slug": "q3-teardown", "version": 1, "change_seq": 4812 }
```

`labels` are label **names**, and creating a note with a label that doesn't exist yet
creates it. Slugs are derived from the title when you omit one.

### Search

`GET /api/v1/w/{ws}/search?q=…&type=…&limit=20` — full-text across the workspace.
`type` narrows to one kind of item (`note`, `post`, `card`, `event`, `file`); omit it to
search everything. Returns `{"items": [...]}`. Needs the `search` module scope.

### Favorites

`POST /api/v1/w/{ws}/favorites` with `{"item_type":"note","item_id":"…","on":true}`.

---

## 4. Labels

One set per workspace, shared by notes, cards, and events.

| method | path | body |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/labels` | → `{items, max}` |
| `POST` | `/api/v1/w/{ws}/labels` | `{name, color?}` |
| `PATCH` | `/api/v1/w/{ws}/labels/{id}` | `{name?}` |
| `DELETE` | `/api/v1/w/{ws}/labels/{id}` | |

You rarely need these directly — passing `labels: ["research"]` when creating a note or
a card creates the label if it is missing.

---

## 5. Board (kanban)

| method | path | body |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/boards` | → summaries with `card_count` |
| `POST` | `/api/v1/w/{ws}/boards` | `{name?, slug?, description?, columns?}` |
| `GET` | `/api/v1/w/{ws}/boards/{board}` | id or slug; returns columns **with their cards** |
| `DELETE` | `/api/v1/w/{ws}/boards/{board}` | |
| `POST` | `/api/v1/w/{ws}/boards/{board}/columns` | `{name, after?, wip_limit?}` |
| `PATCH` | `/api/v1/w/{ws}/columns/{id}` | `{name?, after?, wip_limit?}` |
| `DELETE` | `/api/v1/w/{ws}/columns/{id}` | |
| `POST` | `/api/v1/w/{ws}/boards/{board}/cards` | `{column, title, body?, after?, labels?, due_at?}` |
| `PATCH` | `/api/v1/w/{ws}/cards/{id}` | see below |
| `DELETE` | `/api/v1/w/{ws}/cards/{id}` | |

`columns` on create seeds the board; omit it for the usual three, pass `[]` for an empty
board. `column` on a card is a column id or name.

**Ordering.** Cards and columns carry a `rank` string and are positioned relative to a
sibling, never by index. On `PATCH /cards/{id}` the `after` field is three-valued:

- **absent** — don't move it
- **`null`** — move to the top of the column
- **an id** — drop it directly below that card

Moving a card between columns is `{"column": "Done"}`; completing one is
`{"completed": true}`, which stamps `completed_at`. `base_version` is checked for
content edits (`title`/`body`) only — a move never conflicts with an edit.

---

## 6. Calendar

| method | path | body / query |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/calendars` | |
| `POST` | `/api/v1/w/{ws}/calendars` | `{name?, slug?, color?, timezone?}` |
| `DELETE` | `/api/v1/w/{ws}/calendars/{cal}` | |
| `GET` | `/api/v1/w/{ws}/events` | `?from=&to=&calendar=` (RFC-3339) |
| `POST` | `/api/v1/w/{ws}/events` | `{calendar?, title, starts_at, ends_at?, description?, location?, all_day?, timezone?, rrule?}` |
| `PATCH` | `/api/v1/w/{ws}/events/{id}` | `{base_version?, title?, starts_at?, …, recurrence_id?}` + `?scope=` |
| `DELETE` | `/api/v1/w/{ws}/events/{id}` | `?scope=` |

Times are RFC-3339. Listing expands recurring series across the window, so an occurrence
you get back may not be a stored row: it carries `series_id`, `recurrence_id`, and
`is_override`.

**Editing a repeating event asks which one you mean.** `?scope=this` (the default)
edits the single occurrence named by `recurrence_id`, splitting it out as an override.
`?scope=all` edits the whole series. These are genuinely different operations and
guessing is how people lose meetings — pass the one you mean.

---

## 7. Drive

Bytes never pass through the API server. Uploading is three calls with a direct `PUT` in
the middle:

1. **`POST /api/v1/w/{ws}/files/presign`** — `{name, size, content_type?, folder?}` →
   `{upload_id, url, expires_in}`. The URL is valid for 30 minutes.
2. **`PUT` the bytes to that URL yourself**, with a matching `content-type` header and
   no credentials. This is a plain HTTP request to object storage, not to Octaweave —
   most agent HTTP tools can't do it, so shell out:
   ```bash
   curl -X PUT --upload-file ./chart.png -H 'content-type: image/png' "$URL"
   ```
3. **`POST /api/v1/w/{ws}/files/confirm`** — `{upload_id}`. Until you confirm, the
   object exists but no file row does; abandoned uploads expire on their own, so a
   failed `PUT` needs no cleanup.

| method | path | |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/folders/{id}/contents` | `{id}` is a folder id or the literal **`root`** → `{folders, files}` |
| `POST` | `/api/v1/w/{ws}/folders` | `{name, parent?}` |
| `PATCH` | `/api/v1/w/{ws}/folders/{id}` | `{name?, parent?}` |
| `DELETE` | `/api/v1/w/{ws}/folders/{id}` | |
| `GET` | `/api/v1/w/{ws}/files/{id}` | metadata |
| `PATCH` | `/api/v1/w/{ws}/files/{id}` | `{name?, folder?, trashed?}` |
| `DELETE` | `/api/v1/w/{ws}/files/{id}` | `?force=1` — see below |
| `GET` | `/api/v1/w/{ws}/files/{id}/download` | the bytes; `?inline=1` for a renderable response |
| `POST` | `/api/v1/w/{ws}/files/{id}/share` | → `{url, inline}` — mint a public link |
| `DELETE` | `/api/v1/w/{ws}/files/{id}/share` | revoke it |
| `GET` | `/api/v1/w/{ws}/trash` | |
| `GET` | `/api/v1/w/{ws}/usage` | bytes used against the workspace quota |

**Public links are minted once and unrecoverable.** `shares` stores a hash, so the
`public_url` field is populated only in the response that created it. Afterwards all the
API will tell you is `shared: true`. Store the URL when you get it.

**Deleting a file that a post displays** returns `409` listing what it breaks; the file's
`used_by` field says the same thing up front. Pass `?force=1` to delete anyway. This
exists because a broken image is invisible to the person who broke it — they are signed
in, and it only 404s for readers.

**Uploaded types are never echoed back.** A shared file is served through our origin with
a content-type from a strict raster allowlist (`png`, `jpeg`, `gif`, `webp`, `avif`,
`bmp`, `x-icon`). Everything else — PDFs, zips, and **SVG** — downloads instead of
rendering. `inline: false` in the share response tells you which you got, so don't build
an `<img src>` around a file that came back `false`.

Workspaces have a storage quota (10 GiB by default). Presign refuses past it.

---

## 8. Blog

Posts are notes with a publication clock. Same markdown, same `[[links]]`, same
`base_version` rule.

| method | path | body |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/blog` | the public page's settings |
| `PATCH` | `/api/v1/w/{ws}/blog` | `{title?, tagline?, is_public?, accent?, og_image?, page_size?}` |
| `GET` | `/api/v1/w/{ws}/posts` | `?status=draft\|scheduled\|published\|archived`, `?label=`, `?limit=`, `?cursor=` |
| `POST` | `/api/v1/w/{ws}/posts` | `{title?, body?, excerpt?, slug?, labels?, cover_url?, canonical_url?, author_id?}` |
| `GET` | `/api/v1/w/{ws}/posts/{post}` | id or slug |
| `PATCH` | `/api/v1/w/{ws}/posts/{post}` | `{base_version?, …}` |
| `DELETE` | `/api/v1/w/{ws}/posts/{post}` | |
| `POST` | `/api/v1/w/{ws}/posts/{post}/publish` | `{at?}` — RFC-3339 |
| `POST` | `/api/v1/w/{ws}/posts/{post}/unpublish` | |
| `POST` | `/api/v1/w/{ws}/posts/{post}/archive` | |
| `POST` | `/api/v1/w/{ws}/posts/{post}/preview` | a shareable draft link |

`publish` with `at` in the future **schedules**; in the past **backdates**; absent means
now. Publishing needs `blog:publish` (or plain `write`).

A post has both `status` (what you set) and `visibility` (what a reader gets:
`draft`, `scheduled`, `live`, `archived`) — read `visibility` when you want to know
whether anyone can actually see it. `public_url` is `null` until something is published,
so a link built from it never 404s.

`GET` one post returns `media`: the drive files it displays, and whether a logged-out
reader can actually see each one. Check it after writing a post that embeds images.

### The public blog, unauthenticated

- `GET /api/v1/public/blog/{org}/{ws}`
- `GET /api/v1/public/blog/{org}/{ws}/posts/{slug}`

No key needed, same visibility rules, rate-limited separately.

---

## 9. Studio (image generation)

**This module spends money.** Generations are billed in credits against the
organization, and a generation the provider's content policy blocks still costs credits
because the compute happened.

| method | path | body |
|---|---|---|
| `GET` | `/api/v1/w/{ws}/studio/models` | → `{items, available_credits, configured, notice}` |
| `POST` | `/api/v1/w/{ws}/studio/generations` | `{model, prompt, negative_prompt?, image_size?, num_images?, seed?, idempotency_key?}` |
| `GET` | `/api/v1/w/{ws}/studio/generations/{id}` | poll this |
| `GET` | `/api/v1/w/{ws}/studio/generations` | `?limit=` |

Call `models` first — it returns the live model list with `credits_per_image`,
`max_images`, and the `sizes` each accepts, plus the org's `available_credits`. Model
ids today are `fal-ai/flux/schnell`, `fal-ai/flux/dev`, and `fal-ai/fast-sdxl`, but read
the endpoint rather than hardcoding: prices live in the server, not in config.

`POST` returns `202` with `{id, status: "running", model, quoted_credits}` and does the
work in the background. Poll the generation by id until `status` leaves `running`.
Results land in the workspace drive.

**Always pass `idempotency_key`** — a stable string of your own. A retry with the same
key returns the original generation instead of paying for a second one. Without it, a
timeout you retry is a double charge.

`402 payment_required` means the org is out of credits. `503 not_configured` means
Studio (or object storage — a generation with nowhere to put the result is a charge for
nothing) is not set up on this deployment.

---

## 10. Working well in someone else's workspace

- **Read before you write.** A workspace is a place people work in. `GET` the note or
  card first, keep its `version`, and send it back as `base_version`.
- **Never `DELETE` on a hunch.** Trash (`PATCH {"trashed": true}`) is reversible;
  `DELETE` is not, and `?force=1` on a file breaks published posts.
- **Prefer the narrowest scope.** If the job is reading notes, ask for `notes:read`.
- **Respect 429.** 600 requests/minute per key. Back off; don't hammer.
- **Don't paste the token anywhere.** Not into a note, not into a card body, not into a
  commit. It is shown once and it is the whole workspace.
- **Say what you changed.** Titles and card bodies are read by people. Write them as if
  a colleague will open the board tomorrow, because one will.
