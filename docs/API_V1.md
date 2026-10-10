# Lievik App API (v1)

The JSON API behind the native apps (Android first). It covers everything the web
interface can do, so a native client has full parity with the web/PWA. The web
interface stays the reference implementation: every endpoint here reuses the same
models, services, jobs, billing gate and translations as the matching web
controller, and a behaviour change belongs in that shared code, not in one of the
two front ends.

This is separate from the MCP endpoint (`POST /mcp`, see `docs/API.md`), which is a
small tool surface for agents. Both accept the same bearer tokens.

## Conventions

- Base path: `/api/v1`. JSON in, JSON out (`Content-Type: application/json`).
- Auth: `Authorization: Bearer lvk_…` on everything except `/meta` and `/auth/*`.
  Missing/invalid/expired token → `401 {"error":"unauthorized","code":"unauthorized"}`.
- Locale: server messages (`notice`, `error`) are translated. Resolution:
  `?locale=` → `Accept-Language` → the user's saved locale → `en`. The app sends
  `Accept-Language` set to its own UI language.
- Timestamps: ISO 8601 UTC strings (`2026-10-09T12:34:56Z`).
- Ids: integers, except `external_id`, `invoice_id`, `session_id`.
- Pagination: `?page=` (1-based) and optional `?per=` (max 100). List responses carry
  `"meta": {"page":1,"per":50,"total_pages":3,"total_count":123}`.
- Errors: `{"error": "<translated message>", "code": "<machine code>", "details": {...}}`
  (`details` only when there is something to say).
  Validation errors are `422` with `code: "invalid"` and
  `details: {"field": ["message", …]}`. Not found (including another user's
  record) is `404 code:"not_found"`. A missing wrapper object (e.g. `{"source": …}`)
  is `400 code:"bad_request"` with `details: {"source": ["is missing"]}`.
- An action the web answers with a flash *alert* (nothing was done: empty selection,
  job already finished, manual source can't be refreshed, …) answers `422` with the same
  translated text in `error` and `code` `"invalid"`, or `"no_selection"` / `"no_match"`
  for the bulk actions noted below.
- Mutations that the web answers with a flash notice return `{"notice": "…"}` alongside
  their payload, so the app can show the same toast text the web shows.
- Rate limit: 300 requests/min per token → `429 code:"rate_limited"` with `Retry-After`.

### Billing denials (same as the web)

Paid actions return, before any stream header:

| status | code | meaning |
|---|---|---|
| 402 | `paywall` | no trial and no paid time (body has `billing_url`) |
| 429 | `daily_cap` | daily safety cap for AI requests |
| 503 | `billing_unavailable` | billing is down and nothing cached says the user paid |

Button-style actions (refresh, rate) answer `402 paywall` where the web redirects
to `/billing` (`error` is the web's "needs a trial or paid time" alert). `billing_url`
is the absolute URL of the web billing page. Explicit user actions start the trial exactly as on the web
(`Billing.activate`).

### Server-sent events

Streaming endpoints answer `text/event-stream` with these events, identical to the
web endpoints:

- `event: phase` `data: {"phase":"generating"|"humanizing"|"refining"}`
- `event: chunk` `data: "<json string>"` — a text fragment
- `event: proposal` `data: {…channel proposal…}` (AI channel chat only)
- `event: complete` `data: {...}`
- `event: error` `data: {"message":"…"}`

A request the stream itself rejects (blank question or instructions, nothing to refine,
a draft without events, bad history) answers `200 text/event-stream` with a single
`error` event, exactly like the web; only billing denials and 404s come before the
stream as JSON. Content generation/refinement ends with `complete {"success":true}`,
RAG chat with `complete {"success":true,"cited_events":[…]}`.

## Meta and versioning

`GET /api/v1/meta` (no auth)

```json
{
  "api_version": 1,
  "build_version": "abc123",
  "instance_name": "Lievik",
  "billing_enabled": true,
  "decision_rating_available": true,
  "locales": ["en","sk","cs","es"],
  "android": {"min_version_code": 1, "latest_version_code": 1, "download_url": "https://…"},
  "nip46_relays": ["wss://…"]
}
```

`android.min_version_code` comes from `ANDROID_MIN_VERSION_CODE` (default 1),
`latest_version_code` from `ANDROID_LATEST_VERSION_CODE`, `download_url` from
`ANDROID_DOWNLOAD_URL` (nullable). An app below `min_version_code` must block and send
the user to update; below `latest` it shows a dismissible update notice.

## Authentication

These endpoints are the shared sign-in contract of our Android apps (the
`nostr-signin` module, vendored in `android/nostr-signin/`); keep them in step with
its README.

Each signed-in device holds its own API token (shown in the web's API token list as
`App: <device name>`, revocable there).

### Signed challenge (NIP-55 Amber, or any local signer)

1. `POST /api/v1/auth/challenge` → `{"challenge":"<64 hex>","domain":"lievik.cypherpunk.today","token_url":"https://lievik.cypherpunk.today/api/v1/auth/token","expires_in":300}`
2. The client signs a NIP-98 HTTP-auth event: kind `27235`, `content: ""`, tags
   `[["u","<token_url>"],["method","POST"],["challenge","<challenge>"]]`, `created_at` = now
   (accepted within the last 5 minutes, up to 1 minute ahead). `u` is compared by host
   and path (TLS ends at the proxy, so the scheme may differ).
   Older builds signed kind `22242` with `challenge` and `domain` tags (`domain` required,
   equal to the returned `domain`; content `""` or `"Sign in to Lievik"`); that is still
   accepted. Kind 22242 was dropped for the app because signers treat it as NIP-42 relay
   auth: Amber keys its permission on a `relay` tag and its relay whitelist refuses it
   silently.
3. `POST /api/v1/auth/token` `{"signed_event": {…}, "device_name": "Pixel 9"}` →
   `{"token":"lvk_…","user":{…User…}}`. `signed_event` may also be the event as a JSON
   string. The challenge is single-use (consumed even when the proof then fails) and
   expires. Failure → `401 code:"auth_failed"`. A first sign-in creates the account, as on
   the web. Device tokens are named `App: <device_name>` (default `App: Android`, max 60
   chars).
4. Rate limits per IP: 30/min for challenge + token.

### NIP-46 (nostrconnect QR / deep link, or bunker:// paste)

- `POST /api/v1/auth/nostrconnect` → `{"session_id":"…","poll_token":"…","uri":"nostrconnect://…","expires_at":"…"}`.
  The app opens `uri` (Amber and other signers handle `nostrconnect:`) or shows it as a QR.
- `POST /api/v1/auth/bunker` `{"bunker_uri":"bunker://…"}` → same shape without `uri`
  (`{"session_id","poll_token","expires_at"}`); `422 code:"invalid_link"` for a bad URI.
- `POST /api/v1/auth/poll` `{"session_id":"…","poll_token":"…","device_name":"…"}` →
  `{"status":"pending","auth_url":null}` | `{"status":"expired"}` |
  `{"status":"authenticated","token":"lvk_…","user":{…}}`. The token is issued once; the
  session is consumed (a later poll answers `expired`). `poll_token` is a secret returned
  only to the creator (there is no cookie session to bind to); a wrong `poll_token` is
  `404 code:"not_found"`, an unknown or swept `session_id` is `{"status":"expired"}`.
  `auth_url` is set when the signer asks the user to approve in a browser first.
- `503 code:"busy"` when too many logins are pending (same cap and admission lock as
  the web), `429 code:"rate_limited"` per IP (nip46 5/min and 60/min globally, bunker
  10/min, poll 120/min).

### Sign out

`DELETE /api/v1/session` → `204`. Revokes the token used for the request.

## Current user and settings

`GET /api/v1/me`

```json
{
  "user": {
    "id": 1, "npub": "npub1…", "pubkey_hex": "…", "display_name": "…", "username": "…",
    "about": "…", "picture_url": "…",
    "settings": {
      "locale": "sk", "rating_engine": "chat",
      "event_link_template": "https://yakihonne.com/note/{eventid}",
      "naddr_link_template": "…", "profile_link_template": "…",
      "system_prompt": "…", "default_content_style": "…"
    }
  },
  "stats": {"sources": 3, "channels": 4, "events": 1200, "embedded": 1180},
  "billing": {…BillingStatus…}
}
```

`PATCH /api/v1/me` `{"user": {"locale","rating_engine","event_link_template","naddr_link_template","profile_link_template","system_prompt","default_content_style"}}` → `{"user":…, "notice":…}`
(the notice is in the newly chosen locale). `?locale=` on other requests is not saved.
`POST /api/v1/me/refresh_profile` → `{"notice"}` (queues `RefreshUserProfileJob`).
`POST /api/v1/me/reindex` → `{"notice"}` (queues `ReindexEmbeddingsJob`).

### Content templates

`GET /api/v1/templates` → `{"templates":[{"index":0,"name":"…","template":"…"}], "defaults":[{"name","template"}]}`
`POST /api/v1/templates` `{"name","template"}` → `201 {"template":{"index","name","template"},"notice"}`
(blank values get the web's defaults) · `PATCH /api/v1/templates/:index` `{"name"?,"template"?}` →
`{"template","notice"}` · `DELETE /api/v1/templates/:index` → `{"notice"}`. An index that
does not exist → `404 code:"not_found"`.

### API tokens

`GET /api/v1/api_tokens` → `{"api_tokens":[{"id","name","preview","created_at","last_used_at","expires_at","current":true}]}`
`POST /api/v1/api_tokens` `{"name"}` → `201 {"api_token":{…},"plain_token":"lvk_…"}` (shown once; blank name → `422`)
`DELETE /api/v1/api_tokens/:id` → `{"notice"}`

## Dashboard

`GET /api/v1/dashboard` → `{"stats":{…},"active_jobs":[ActivityLog…],"recent_events":[Event…20]}`
(sweeps stale activity logs first, like the web).
`POST /api/v1/dashboard/rate_all` → `{"notice","queued_channels":4}` (paid access).

## Sync (local-first cache)

`GET /api/v1/sync?since=<iso8601|blank>&cursor=<opaque>`

Lets the app keep a local database and only fetch what changed. `since` blank =
full initial sync (events limited to the last `import_days` max of 180 days, newest
first, paginated through `cursor`).

Details:
- The window is the largest `import_days` of the user's sources (default 30), capped
  at 180 days, counted back from `server_time`, on `published_at`. Both `events` and
  `channel_events` (via their event) are limited to it, in initial and incremental sync.
- Initial sync orders events by `published_at` desc, channel_events by id. Incremental
  sync returns rows whose `updated_at` is after `since` minus 5 seconds (a row may come
  twice across syncs; upserts make that harmless), ordered by `updated_at`.
- On later pages send only `cursor` (it carries `since`). `server_time` is fixed when the
  first page is served and repeated on every page, so storing it after the last page
  cannot skip changes made while paging.
- Ratings and used/unused flags (also the web's bulk actions and publishing a draft) bump
  `channel_events.updated_at`; event `top_channels` is derived, so recompute it locally
  from channel_events rather than expecting the event to change.
- A garbled `cursor` or `since` → `422 code:"invalid"`.

```json
{
  "server_time": "2026-10-09T12:00:00Z",
  "sources": [Source…],            // always the full list (small), including the manual source
  "channels": [Channel…],          // always the full list (small)
  "events": [Event…],              // created/updated after since, ≤ 500 per page
  "channel_events": [ChannelEvent…], // created/updated after since, ≤ 2000 per page
  "next_cursor": "…" | null
}
```

The client replaces its source and channel tables with the returned lists, deletes
local events whose source no longer exists and channel_events whose channel no
longer exists, upserts the rest, and stores `server_time` as the next `since` once
`next_cursor` is null.

## Representations

**Source**
`{"id","source_type":"nostr|rss|manual","identifier","name","description","distance","settings":{"include_replies","include_reposts","import_days"},"event_count","created_at","updated_at"}`

**Channel**
`{"id","name","description","language","prompt","content_prompt","content_language","content_style","settings":{"relevance_threshold":50,"humanize_output":true},"pending_count","created_at","updated_at"}`
(`pending_count`: unused events at or above the threshold, as on the web channel list)

**Event**
```json
{
  "id": 1, "source_id": 2, "source_name": "…", "source_type": "nostr",
  "external_id": "…", "event_type": "original|reply|repost|long_form", "kind": 1,
  "content": "raw content", "title": "for 30023/rss, nullable",
  "published_at": "…", "updated_at": "…",
  "author": {"name": "…", "picture_url": "…", "npub": "…"},
  "source_url": "link to the original (user's link template / rss link)",
  "nostr_uri": "nostr:nevent1… (naddr1… for long-form); null unless a nostr source",
  "images": ["https://…"],
  "references": [
    {"uri":"nostr:npub1…","type":"profile","label":"@Name","url":"https://…","npub":"npub1…"},
    {"uri":"nostr:nevent1…","type":"event","label":"Author","preview":"…300 chars","url":"…"},
    {"uri":"nostr:naddr1…","type":"article","label":"slug or title","url":"…"}
  ],
  "top_channels": [{"channel_id":3,"channel_name":"…","relevance_score":87,"used":false}]
}
```
`references` is resolved with the same local-first logic as the web view
(`Nostr::ReferenceResolver`, which also renders the web's HTML); an unresolved profile
falls back to a truncated npub, an unresolved note has `label` "Referenced note" (translated)
and `preview: null`; an identifier that does not decode is left out. Each distinct `uri`
is listed once, spelled exactly as in `content`. The client replaces each `uri`
occurrence in `content` with the reference rendering.

`kind` is the Nostr kind (null for RSS/manual). `title`: RSS item title or the long-form
`title` tag. `author`: the source's label (as the web shows it), the npub of the signing
key and a picture from a Lievik user with that key or the relay profile cache (nullable);
for RSS/manual only `name`. `images`: http(s) URLs in the content with an image extension,
NIP-92 `imeta` URLs and a long-form `image` tag. `top_channels`: up to 3 unused channel
ratings, best first (like the web cards), so `used` is always false there.

**ChannelEvent**
`{"id","channel_id","event_id","relevance_score","relevance_reason","used","used_at","updated_at","engine":"chat|decision|null"}`

**ActivityLog**
`{"id","activity_type","status","message","progress","metadata":{…},"created_at","updated_at","completed_at","dev_log_count","stale":false}`

**ChannelContent**
`{"id","channel_id","title","content","generation_prompt","status":"draft|published","published_at","event_ids":[…],"versions_count","created_at","updated_at"}`

**BillingStatus** (with billing off: `enabled:false, state:"active", allows:true`)
```json
{
  "enabled": true,
  "state": "active|trial|expired|none|unknown",
  "allows": true,
  "until": "…|null",
  "other_products": [{"product":"all-access","state":"active","until":"…"}],
  "npub": "npub1…"
}
```

## Sources

- `GET /api/v1/sources` → `{"sources":[Source…]}` (manual source excluded, like the web)
- `GET /api/v1/sources/:id` → `{"source":Source}`; `GET /api/v1/sources/:id/events?page=` → `{"events":[Event…],"meta"}`
- `POST /api/v1/sources` `{"source":{"source_type","identifier","name","description","distance","settings_include_replies","settings_include_reposts","settings_import_days"}}`
  → `201 {"source","notice","importing":true|false}` (starts the trial, queues ingestion, like the web)
- `PATCH /api/v1/sources/:id` `{"source":{…}}` → `{"source","notice"}` · `DELETE /api/v1/sources/:id` → `{"notice"}`
- `POST /api/v1/sources/:id/refresh` → `{"notice"}` (`422` for a manual source) ·
  `POST /api/v1/sources/refresh_all` → `{"notice","count"}` (paid access)

## Channels

- `GET /api/v1/channels` → `{"channels":[Channel…]}` (with `pending_count`)
- `GET /api/v1/channels/:id` → `{"channel":Channel,"used_count","unused_count","default_prompt_template"}`
- `GET /api/v1/channels/new` → `{"channel": {…Channel without id/pending_count/timestamps…}}` (defaults: prompt template, the user's content_style)
- `POST /api/v1/channels` `{"channel":{"name","description","language","prompt"}}` → `201 {"channel","notice","queued":N}`
- `PATCH /api/v1/channels/:id` `{"channel":{name, description, language, prompt, content_prompt, content_language, content_style, settings:{relevance_threshold, humanize_output}}}`
  (the web's edit and settings forms combined) → `{"channel","notice"}`. `settings` is merged
  into the existing settings, so sending only `humanize_output` keeps the threshold.
- `DELETE /api/v1/channels/:id` → `{"notice"}`
- `POST /api/v1/channels/:id/rate` (paid access) — rate new events → `{"notice"}`

### Channel events (the curation queue)

- `GET /api/v1/channels/:id/events?show_used=true&search=&sort=relevance|newest|oldest&page=`
  → `{"items":[{"channel_event":ChannelEvent,"event":Event}],"meta","used_count","unused_count","threshold"}`
  Same filtering as the web channel page: above threshold, unused only unless `show_used`.
- `POST /api/v1/channels/:id/events/mark_used` `{"event_ids":[…]}` → `{"notice","count"}`
- `POST /api/v1/channels/:id/events/mark_unused` `{"event_ids":[…]}` → `{"notice","count"}`
- `POST /api/v1/channels/:id/events/rate` `{"event_ids":[…]}` (paid access) → `{"notice","count"}`
- An empty selection (or, for rate, no ids among the user's own events) → `422 code:"no_selection"`.
  `count` is the number of rows changed / events queued; ids of other users' events are ignored.

### Content builder

- `GET /api/v1/channels/:channel_id/contents` → `{"drafts":[ChannelContent…],"published":[…]}`
- `GET /api/v1/channels/:channel_id/contents/:id` → `{"content":ChannelContent,"events":[Event…]}`
- `POST /api/v1/channels/:channel_id/contents` `{"channel_content":{"title","generation_prompt"},"event_ids":[…]}` → `201 {"content","notice"}`
  (`event_ids` resolve through the user's own events; others are dropped)
- `PATCH …/contents/:id` `{"channel_content":{"title","content","generation_prompt"}}` (saves a version when content changes) → `{"content","notice"}`
- `DELETE …/contents/:id` → `{"notice"}`
- `POST …/contents/:id/generate` → SSE (generating → humanizing → complete). Paid AI.
- `POST …/contents/:id/refine` `{"user_prompt":"…"}` → SSE (refining → humanizing → complete). Paid AI.
- `POST …/contents/:id/publish` → `{"content","notice"}`
- `POST …/contents/:id/revert` → `{"content","notice"}` or `422 code:"no_previous"`

On `complete`, the client re-fetches the content (the server saved it post-processed:
fences stripped, nostr URIs replaced with the user's link templates).

## Events

- `GET /api/v1/events?source_id=&event_type=&search=&page=` → `{"events":[Event…],"meta","filter_sources":[{"id","name","source_type"}]}`
- `GET /api/v1/events/:id` → `{"event":Event,"channel_events":[ChannelEvent + "channel_name"],"linked_contents":[{"url","title","summary","fetched_at"}]}`
- `POST /api/v1/events/rate` `{"event_ids":[…]}` or the filter params (rates the filtered set, capped) — paid access
  → `{"notice","count"}` (the web's notice, including the "skipped, max 2000" sentence);
  nothing matching or no channels → `422 code:"no_match"`.
- `POST /api/v1/events/:id/mark_used` `{"channel_event_ids":[…]}` → `{"notice","count"}` (empty → `422 code:"no_selection"`)
- `POST /api/v1/manual_events` `{"content":"…"}` (or `{"event":{"content"}}`) → `201 {"event","notice"}`; blank → `422` with `details.content`

## Ask (RAG chat)

- `GET /api/v1/chat` → `{"embedded_count","total_count"}`
- `POST /api/v1/chat/stream` `{"question":"…","history":[{"role":"user|assistant","content":"…"}]}` → SSE
  (`chunk`…, `complete {"success":true,"cited_events":[{"id","content","source_name","published_at"}]}`). Paid AI.

## AI channel creation

- `POST /api/v1/channels/ai/stream` `{"message","history":[…]}` → SSE (`chunk`, `proposal`, `complete`, `error`). Paid AI.
- `POST /api/v1/channels/ai/bulk_create` `{"channels":[…proposal channels…],"templates":[{"name","template"}]}` → `{"count","notice"}`
  (queues initial rating per channel like the web; no channels or an invalid one → `422 code:"invalid"`)

## Activity

- `GET /api/v1/activity_logs?page=` → `{"activity_logs":[…],"meta","active":[…],"stale_count"}`
- `GET /api/v1/activity_logs/active` → `{"active":true,"jobs":[ActivityLog…]}` (sweeps stale first; poll this)
- `GET /api/v1/activity_logs/:id/dev_logs?page=` → `{"dev_logs":[{"id","log_type","message","details","created_at"}],"meta"}`
- `POST /api/v1/activity_logs/:id/cancel` → `{"notice"}` (already finished → `422`) ·
  `POST /api/v1/activity_logs/:id/retry` (paid access) → `{"notice"}` (no channel → `422`) ·
  `POST /api/v1/activity_logs/cleanup_stale` → `{"notice","count"}`

## Billing

All `404 code:"not_found"` when billing is not configured (self-hosted), exactly like
`/billing`.

- `GET /api/v1/billing` → `{"status":BillingStatus,"plans":[{"plan":"lievik","sats":15000,"days":30},{"plan":"all-access",…}],"min_sats":1000,"max_sats":1000000,"pending_charges":[{"invoice_id","plan","checkout_url"}]}`.
  Also settles any of this user's recorded charges that have been paid (like the web
  page does), returning `"notice"` when one just settled.
- `POST /api/v1/billing/trial` → `{"status","notice"}` (`notice` null when no trial was started)
- `POST /api/v1/billing/charges` `{"plan":"lievik|all-access","sats":optional}` →
  `{"invoice_id","checkout_url"}`. The app opens `checkout_url` in a browser tab
  (Custom Tab); BTCPay's return goes to the web billing page. Unknown plan or `sats`
  outside `min_sats..max_sats` → `422 code:"invalid"`; billing failing → `503 code:"billing_unavailable"`.
- `GET /api/v1/billing/charges/:invoice_id` → `{"settled":true|false,"status":BillingStatus,"notice"?}`.
  Only charges this user created through the API can be polled (a per-user ledger kept
  24 h in the server cache, the API counterpart of the web's session ledger); anything
  else → `404 code:"not_found"`. A settled or dead charge leaves the ledger, so the paid
  notice is reported once.
