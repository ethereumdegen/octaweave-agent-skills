# Octaweave

Octaweave is a workspace — notes, a kanban board, a drive, a calendar, a blog, and an
image studio — that a person uses in a browser and you use over HTTP. Same objects, same
permissions. Whatever you write, a human sees a second later.

Codex has no progressive skill loading, so the working set is inline below. The complete
endpoint reference is `API.md` next to this file — read it before doing anything this
page doesn't cover.

## Credentials

```bash
export OCTAWEAVE_API_KEY=owk_live_…      # workspace → Keys → Create
```

Every request: `Authorization: Bearer $OCTAWEAVE_API_KEY`. Base URL
`https://octaweave.com`, everything under `/api/v1`. If the variable isn't set, say so
and stop — don't invent a key or go looking through the user's dotfiles for one.

**Start every session with `whoami`.** A key is pinned to exactly one workspace and this
is the only reliable way to learn which:

```bash
curl -s https://octaweave.com/api/v1/whoami -H "Authorization: Bearer $OCTAWEAVE_API_KEY"
# → { "actor": { "workspace_id": "9f2c…" }, … }
```

Use `actor.workspace_id` as `{ws}` in every path. Guessing a slug gets you `403`, not
`404`, which reads like a broken key and sends you debugging the wrong thing.

## Rules

**Send `base_version` on every edit.** Notes, posts, cards, and events carry a `version`.
`GET` first, keep the `version`, send it as `base_version` on the `PATCH`. A mismatch is
`409 stale_write` with the current object under `"current"` — merge against it and retry.
Omitting `base_version` is last-write-wins and will silently destroy a human's edit.

**Deletes are real.** `PATCH {"trashed": true}` is reversible; `DELETE` is not. Deleting
a file that a published post displays returns `409` naming what it breaks — don't
reflexively retry with `?force=1`, ask the user.

**Studio spends money.** Generations bill the organization's credits, and one the
provider's content policy blocks still costs them. Check `available_credits` first,
always pass `idempotency_key`, never generate images unprompted.

**Errors are always `{"error": "...", "code": "..."}`.** Codes: `bad_request`,
`unauthorized`, `forbidden`, `not_found`, `conflict`, `stale_write`, `payment_required`,
`rate_limited` (600/min per key), `not_configured` (module disabled here),
`database_unavailable`, `upstream_error`. Lists return `{"items": [...]}`; notes and
posts add `next_cursor`.

## Endpoints

All paths prefixed `/api/v1`. `{ws}` is the workspace from `whoami`.

**Notes** — markdown is the source of truth; `[[slug]]` links between notes are tracked.
Search covers notes, posts, and cards only — events and drive files are not indexed, so
list those modules directly rather than reading an empty result as "nothing there".
```
GET    /w/{ws}/notes                 ?label= &sort=updated|accessed &limit= &cursor=
POST   /w/{ws}/notes                 {title?, body?, slug?, labels?}
GET    /w/{ws}/notes/{note}          id or slug; returns body, html, backlinks, broken_links
PATCH  /w/{ws}/notes/{note}          {base_version?, title?, body?, slug?, labels?}
DELETE /w/{ws}/notes/{note}
GET    /w/{ws}/search                ?q= &type=note|post|card &limit=
```

**Board** — position is relative, never an index.
```
GET    /w/{ws}/boards
GET    /w/{ws}/boards/{board}        columns with their cards
POST   /w/{ws}/boards/{board}/cards  {column, title, body?, after?, labels?, due_at?}
PATCH  /w/{ws}/cards/{id}            {base_version?, title?, body?, column?, after?, completed?, labels?}
DELETE /w/{ws}/cards/{id}
```
On `PATCH`, `after` is three-valued: **absent** = don't move, **`null`** = top of column,
**an id** = directly below that card. `base_version` is checked for `title`/`body` only.

**Calendar** — RFC-3339 times; listing expands recurring series.
```
GET    /w/{ws}/calendars
GET    /w/{ws}/events                ?from= &to= &calendar=
POST   /w/{ws}/events                {calendar?, title, starts_at, ends_at?, all_day?, rrule?, …}
PATCH  /w/{ws}/events/{id}?scope=    {base_version?, recurrence_id?, …}
DELETE /w/{ws}/events/{id}?scope=
```
`scope=this` (default) edits one occurrence; `scope=all` edits the series. Pass the one
you mean — guessing is how people lose meetings.

**Drive** — bytes never pass through the API server.
```
GET    /w/{ws}/folders/{id}/contents   {id} is a folder id or the literal `root`
POST   /w/{ws}/files/presign           {name, size, content_type?, folder?} → {upload_id, url}
POST   /w/{ws}/files/confirm           {upload_id}
POST   /w/{ws}/files/{id}/share        → {url, inline}
PATCH  /w/{ws}/files/{id}              {name?, folder?, trashed?}
GET    /w/{ws}/usage
```
Upload is presign → **`curl -X PUT --upload-file ./f.png -H 'content-type: image/png'
"$URL"`** → confirm. The `PUT` goes to object storage, not to Octaweave, and carries no
credentials. A public link from `share` is returned **once** and is unrecoverable
afterwards — save it immediately. `inline: false` means the file downloads rather than
renders (PDFs, zips, SVG), so don't wrap it in an `<img src>`.

**Blog**
```
GET    /w/{ws}/posts                 ?status=draft|scheduled|published|archived
POST   /w/{ws}/posts                 {title?, body?, excerpt?, slug?, labels?, cover_url?}
PATCH  /w/{ws}/posts/{post}          {base_version?, …}
POST   /w/{ws}/posts/{post}/publish  {at?} — future schedules, past backdates, absent = now
```
Read `visibility` (`draft`/`scheduled`/`live`/`archived`) to know what a reader gets.
`GET` one post returns `media` — the drive files it displays and whether a logged-out
reader can actually see each one. Check it before publishing something with images.

**Studio**
```
GET    /w/{ws}/studio/models              → {items, available_credits, configured}
POST   /w/{ws}/studio/generations         {model, prompt, num_images?, seed?, idempotency_key?}
GET    /w/{ws}/studio/generations/{id}    poll until status leaves "running"
```

## Reporting back

Give the user the `public_url` or workspace path of what you touched, not just "done" —
they will want to look at it. Never echo the API key into a note, a card, a commit
message, or the transcript.
