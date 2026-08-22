---
name: octaweave
description: Read and write an Octaweave workspace over its HTTP API — notes, kanban cards, drive files, calendar events, blog posts, and image generation. Use whenever the user asks to look something up in, add something to, or update their Octaweave workspace, or mentions octaweave.com, a workspace slug, or an owk_ API key.
---

# Octaweave

Octaweave is a workspace — notes, a board, a drive, a calendar, a blog, an image studio —
that a person uses in a browser and you use over HTTP. Same objects, same permissions.
Whatever you write, a human sees a second later.

**`reference/api.md` is the full endpoint reference.** Read it before your first write of
a session; this file is the operating procedure around it.

## Setup

One environment variable, a workspace API key:

```bash
export OCTAWEAVE_API_KEY=owk_live_…      # workspace → Keys → Create
```

Every request carries it:

```
Authorization: Bearer $OCTAWEAVE_API_KEY
```

If it isn't set, say so and stop — don't invent a key or scrape one out of the user's
dotfiles. Self-hosted deployments swap the host; default to `https://octaweave.com`.

## Always start with whoami

```bash
curl -s https://octaweave.com/api/v1/whoami -H "Authorization: Bearer $OCTAWEAVE_API_KEY"
```

A key is pinned to **exactly one workspace**, and `actor.workspace_id` in that response
is which. Use it as `{ws}` in every subsequent path rather than guessing a slug — a
wrong workspace is a `403`, not a `404`, and reads as a broken key.

It is also the cheapest proof the key works, which is worth one request before a long
sequence of writes.

## The three rules that matter

**1. Send `base_version` on every edit.** Notes, posts, cards, and events carry a
`version`. `GET` the object, keep its `version`, send it back as `base_version` on the
`PATCH`. A mismatch returns `409 stale_write` with the current object under `"current"` —
merge against that and retry. Omitting `base_version` is last-write-wins, which
silently destroys whatever a human typed while you were thinking.

**2. Deletes are real.** `PATCH {"trashed": true}` on a file is reversible; `DELETE` is
not. `DELETE` a file that a published post displays and the API returns `409` listing
what breaks — do not reflexively retry with `?force=1`. Ask.

**3. Studio spends money.** `POST /studio/generations` bills the organization's credits,
and a generation the provider's content policy blocks still costs them. Check
`available_credits` from `/studio/models` first, always pass an `idempotency_key` so a
retry doesn't double-charge, and don't generate images the user didn't ask for.

## Common jobs

**Capture a note.** `POST /api/v1/w/{ws}/notes` with `{title, body, labels}`. Body is
markdown; `[[slug]]` links to another note and the server tracks the backlink. Labels
are names — passing one that doesn't exist creates it.

**Find something.** `GET /api/v1/w/{ws}/search?q=…` searches the whole workspace; add
`&type=note` (or `post`, `card`, `event`, `file`) to narrow it. This is almost always
better than listing and filtering client-side.

**Move a card.** `PATCH /api/v1/w/{ws}/cards/{id}`. `{"column":"Done"}` moves it,
`{"completed":true}` completes it. Position is relative, never an index: `after` absent
means don't move, `null` means top of the column, an id means directly below that card.

**Upload a file.** Three steps, and the middle one is not an Octaweave request:
`POST /files/presign` → `curl -X PUT --upload-file ./f.png -H 'content-type: image/png'
"$URL"` → `POST /files/confirm {upload_id}`. Then `POST /files/{id}/share` if it needs a
public link — that URL is returned **once** and is unrecoverable afterwards, so save it
into whatever you're writing immediately.

**Publish a post.** Write it as a draft first, `GET` it back and check the `media` array
(it says whether a logged-out reader can actually see each embedded image), then
`POST /posts/{id}/publish`. Pass `{"at": "…"}` to schedule.

## Reporting back

Give the user the `public_url` or the workspace path of what you touched, not just "done".
They will want to look at it. Never echo the API key into a note, a card, a commit
message, or the transcript.
