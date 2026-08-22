---
description: How to work inside an Octaweave workspace — the whoami-first rule, optimistic concurrency with base_version, relative card ordering, the three-step upload, publishing safely, and what the error codes mean
---

# Octaweave Workspace Operations

These tools call the Octaweave API (`https://octaweave.com/api/v1`) authenticated by a
single `OCTAWEAVE_API_KEY` — an `owk_` workspace key minted on the workspace's **Keys**
page. You never pass the token yourself; every tool already carries it.

Two facts about that key shape everything below:

- **It is pinned to exactly one workspace.** There is no org-wide key. Calling another
  workspace returns `403 forbidden` however the scopes read.
- **It cannot mint another key.** A leaked read-only key cannot escalate itself, and you
  cannot create one to widen your own access.

## Orient yourself first

**`octaweave_whoami`** — always the first call. It returns
`{user, actor: {type, label, workspace_id}, scopes, is_admin}`. Take
`actor.workspace_id` and pass it as `workspace` to every other tool. Do not guess a slug
from what the user said: a wrong workspace is a `403`, not a `404`, so it reads like a
dead key and sends you debugging the wrong thing.

It is also the cheapest possible proof the key works, which is worth one request before a
long sequence of writes.

`is_admin` is always `false` here by design — the admin surface refuses API keys
outright, so a key handed to an agent is never a site administrator even when an
administrator created it.

## Read before you write — `base_version`

Notes, posts, cards, and events carry a `version`. The rule:

1. `octaweave_get_note` (or `_get_post`, or `_get_board` for a card) — keep the `version`.
2. Send it as `base_version` on the update.
3. If someone edited in between you get **`409 stale_write`**, and the response carries
   the current object under `current`. Merge your change into that and retry with its
   `version`.

Omitting `base_version` is last-write-wins. It will silently destroy whatever a human
typed while you were thinking, and nobody will know it happened. Pass it.

For cards, `base_version` is only checked on content edits (`title`/`body`), so moving a
card never collides with someone else's edit — but still pass it when you change text.

## Notes

- **`octaweave_list_notes`** — `{items, next_cursor}`; summaries only, no bodies. Page by
  passing `next_cursor` back as `cursor` until it comes back `null`.
- **`octaweave_get_note`** — by id **or slug**. Returns `body` (markdown, the source of
  truth), `html` (rendered and sanitized, for display only), `backlinks`, and
  `broken_links` — slugs this note links to that do not exist yet.
- **`octaweave_create_note`** / **`octaweave_update_note`** — `body` is markdown.
  `[[some-slug]]` links to another note and the server tracks the backlink for you.
  `labels` are **names**, and a name that does not exist yet is created.
- **`octaweave_search`** — full text across notes, posts, cards, events, and file names.
  Reach for this before listing a module and filtering yourself. `type` narrows it.

`octaweave_delete_note` is permanent. There is no trash for notes and no undo. Confirm
with the user before deleting anything you did not create in this session.

## Board

`octaweave_get_board` returns every column with its cards in order — that is where card
ids and versions come from, and where you learn the column names.

**Position is relative, never an index.** On `octaweave_update_card`:

| `after` | effect |
|---|---|
| absent | don't move it |
| `null` | move to the top of the column |
| a card id | drop it directly below that card |

Moving between columns is `{"column": "Done"}` (id or name). Completing is
`{"completed": true}`, which stamps `completed_at`.

## Calendar

Times are RFC-3339. `octaweave_list_events` **expands recurring series** across the
window you ask for, so an item you get back may not be a stored row — it carries
`series_id`, `recurrence_id`, and `is_override`.

**Editing a repeating event asks which one you mean.** `scope: "this"` (the default)
edits the single occurrence named by `recurrence_id`, splitting it out as an override.
`scope: "all"` edits the whole series. These are genuinely different operations and
guessing is how people lose meetings — if the user's intent isn't obvious, ask.

## Uploading a file — three steps, and the middle one is `bash`

Bytes never pass through the API server, so the upload is not one tool call:

1. **`octaweave_presign_upload`** with `{name, size, content_type}` → `{upload_id, url}`.
   `size` must be the real byte count. The URL is good for 30 minutes.
2. **PUT the bytes yourself** with the `bash` tool. The URL is already signed and points
   at object storage, not at Octaweave, so it takes no credentials:
   ```bash
   curl -sf -X PUT --upload-file ./chart.png -H 'content-type: image/png' "$URL"
   ```
   The `content-type` must match what you declared in step 1.
3. **`octaweave_confirm_upload`** with the `upload_id`. Until you confirm, the object
   exists but no file does — an abandoned upload expires on its own, so a failed PUT
   needs no cleanup.

**`octaweave_share_file`** mints a public link and returns `{url, inline}`. The URL is
returned **once**: only a hash is stored, so afterwards the API will only tell you
`shared: true`. Save it into whatever you are writing immediately.

`inline: false` means the file will download rather than render — PDFs, zips, and
**SVG** always do, because serving them inline from our own origin would be hosting
arbitrary script there. Don't build an `<img src>` around a file that came back `false`.

**Trash, don't delete.** `octaweave_update_file` with `{"trashed": true}` is reversible.
Deleting a file that a published post displays takes that post's images down for every
reader while looking perfectly fine to the author, who is signed in.

## Blog

Posts are notes with a publication clock — same markdown, same `[[links]]`, same
`base_version` rule.

A post has both `status` (what was set) and `visibility` (what a reader gets: `draft`,
`scheduled`, `live`, `archived`). Read **`visibility`** when the question is "can anyone
see this". `public_url` is `null` until something is published, so a link built from it
never 404s.

Before publishing: `octaweave_get_post` returns a `media` array listing the drive files
the post displays **and whether a logged-out reader can actually see each one**. Check
it. Then `octaweave_publish_post` — `at` in the future schedules, `at` in the past
backdates, omitted publishes now.

Publishing puts writing on the public internet under someone's name. Confirm first.

## Studio

**This spends real money.** Generations bill the organization's credits, and one the
provider's content policy blocks still costs them, because the compute happened and we
paid for it.

1. **`octaweave_studio_models`** — the live model list with `credits_per_image`,
   `max_images`, the `sizes` each accepts, and the org's `available_credits`. Prices live
   in the server, not in config, so read them here rather than assuming.
2. **`octaweave_create_generation`** — returns `202` with
   `{id, status: "running", quoted_credits}`. **Always pass `idempotency_key`**, a stable
   string of your own: a retry with the same key returns the original generation instead
   of paying for a second one. Without it, a timeout you retry is a double charge.
3. **`octaweave_get_generation`** — poll until `status` leaves `running`. Results land in
   the workspace drive.

`402 payment_required` means the org is out of credits. `503 not_configured` means Studio
— or the object storage it writes to — isn't set up on this deployment.

## Errors

Every failure is `{"error": "a readable sentence", "code": "machine_code"}`.

| code | what to do |
|---|---|
| `unauthorized` | the key is missing, revoked, or expired — stop and tell the user |
| `forbidden` | wrong workspace, or the key's scopes don't cover this module |
| `not_found` | no such object **in this workspace** |
| `conflict` | a real collision — duplicate slug, WIP limit hit |
| `stale_write` | you wrote against an old version; merge `current` and retry |
| `payment_required` | out of credits |
| `rate_limited` | 600 requests/minute per key — back off, don't hammer |
| `not_configured` | that module is disabled on this deployment; say so and stop |
| `database_unavailable` | transient — retry with backoff |

## Safety

- Every write lands in a workspace people actually work in. Titles and card bodies get
  read by humans — write them for a colleague opening the board tomorrow.
- Confirm before publishing, before deleting, and before spending credits.
- Never expose the API key or a raw tool URL, and never write the key into a note, a
  card, or a commit message. It is shown once and it is the whole workspace.
