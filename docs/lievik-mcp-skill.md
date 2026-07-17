---
name: lievik-marketing-curator
description: >
  Drive Lievik, a Nostr-first content-curation tool, through its MCP API to answer
  "what should I post, and to which audience?" Use when the user wants to plan a
  newsletter/channel update, find relevant content they already created, see how
  content is rated per audience, or mark content as used. Covers connecting to the
  Lievik MCP endpoint with an API token and the ten available tools.
---

# Lievik Marketing Curator

## What Lievik is

Lievik helps a creator remember **what content matters to which audience, and what they've already shared**. It watches the user's content sources (their Nostr posts, RSS feeds, accounts they follow), and for each **channel** (an audience: a newsletter, a Signal group, course students…) it AI-scores every piece of content 0–100 for relevance and tracks whether it has been used.

The core question Lievik answers: *"It's time to write to this audience — what recent content of mine is relevant, and what have I not already sent them?"*

Key concepts:

- **Source** — where content comes from (`nostr`, `rss`, or `manual`).
- **Event** — one piece of content (a Nostr note, RSS item, or manual entry).
- **Channel** — an audience, with a relevance `prompt` (criteria) and a `relevance_threshold`.
- **Channel rating** — per (event, channel) pair: a `score` (0–100), a `reason`, and `used`/`used_at`.

## How to connect

Lievik exposes an MCP server over HTTP JSON-RPC 2.0.

- **Endpoint**: `POST https://lievik.cypherpunk.today/mcp`
- **Auth**: `Authorization: Bearer <token>` — the user generates a token at **User settings → API Tokens** (`/user/edit`). Tokens start with `lvk_` and are shown only once. The token scopes everything to that one user's data.

If you are an MCP-capable client, register the server:

```json
{
  "mcpServers": {
    "lievik": {
      "url": "https://lievik.cypherpunk.today/mcp",
      "headers": { "Authorization": "Bearer lvk_your_token_here" }
    }
  }
}
```

If you only have an HTTP client, send JSON-RPC directly. Discover tools with `tools/list`; invoke with `tools/call` (`params: { name, arguments }`). Full envelope and error-code reference: see [`API.md`](./API.md).

## The ten tools

**Reading / planning**
- `list_events` — the main feed: recent events, each with ratings from *every* channel. Filter by `since`, `min_score`, `source_type`, `event_type`, `only_unused`.
- `list_channels` — all channels with criteria, threshold, and counts (total/used/unused).
- `list_channel_events` — events rated for one channel, ranked by score (defaults to the channel's own threshold and `only_unused=true`).
- `get_event` — one event in full, including linked-URL titles/summaries.
- `search_events` — semantic embedding search over the user's events.

**Acting**
- `mark_event_used` / `mark_event_unused` — record (or undo) that an event was used in a channel.
- `add_manual_event` — add content manually; links are extracted and the event is rated against all channels.
- `refresh_source` — enqueue re-ingestion of one source (hits relays/RSS; use sparingly).
- `rate_channel` — enqueue (re-)rating of a channel's events.

## Recommended workflow

**"Help me write to audience X":**

1. `list_channels` → find the channel `id` for that audience and read its `prompt`.
2. `list_channel_events` with that `channel_id` (keep `only_unused=true`) → the relevant, not-yet-sent events, best first.
3. For promising candidates, `get_event` to read full content and any linked-article summaries.
4. Draft the update from the selected events, honoring the channel's `prompt` and `language`.
5. After the user confirms what they'll send, `mark_event_used` each event for that `channel_id` so it won't resurface next time.

**"What's new and worth posting anywhere?":** start with `list_events` (`only_unused=true`, a sensible `min_score`, recent `since`) and route each event to the channels whose `channel_ratings` score it highly.

**Finding something specific the user half-remembers:** use `search_events` with a natural-language query.

## Behavior notes

- Ratings are asynchronous. After `add_manual_event`, `refresh_source`, or `rate_channel`, the response confirms enqueueing but scores appear later — re-read with `get_event` / `list_events`.
- All tools are user-scoped: you can only see and modify the token owner's channels, sources, and events. Unknown IDs return an application error (`-32000`).
- `content_resolved` gives event text with Nostr `nostr:` references resolved to readable names — prefer it over raw `content` when drafting.
- Don't mark events used until the user has actually committed to sending them; it's the user's record of what each audience has seen.
