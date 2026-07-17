# Lievik API (MCP)

Lievik exposes its functionality programmatically through a **Model Context Protocol (MCP)** server. This lets AI agents and scripts drive the full marketing-curation loop: see what content you have, how it's rated per channel, decide what to post where, and mark things as used.

There is a single HTTP endpoint that speaks **JSON-RPC 2.0**. Authentication is by API token (`Authorization: Bearer <token>`). Every call acts as the user who owns the token, and only ever sees that user's own data.

- **Endpoint**: `POST /mcp`
- **Production base URL**: `https://lievik.cypherpunk.today`
- **Protocol**: JSON-RPC 2.0 (MCP protocol version `2025-06-18`)
- **Auth**: `Authorization: Bearer <api token>`

## Authentication

### Getting a token

1. Log in to Lievik and open **User settings** (`/user/edit`).
2. Scroll to the **API Tokens** section.
3. Enter a name (e.g. `marketing-agent`) and click **Generate token**.
4. **Copy the token immediately** — it is shown only once.

Tokens look like `lvk_<64 hex chars>`. Only a SHA-256 digest is stored server-side; the plaintext cannot be recovered. Use one token per agent/integration so you can revoke them independently.

### Using a token

Send it in the `Authorization` header on every request:

```
Authorization: Bearer lvk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Requests without a valid, non-expired token get `401 Unauthorized`:

```json
{ "error": "unauthorized" }
```

### Revoking

Revoke any token from the same **API Tokens** section. Revocation is immediate.

## JSON-RPC envelope

Every request is a JSON-RPC 2.0 object. Single requests and batches (arrays) are both supported.

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": { "name": "list_channels", "arguments": {} }
}
```

**Success response:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": { "...": "..." }
}
```

**Error response:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": { "code": -32602, "message": "channel_id required" }
}
```

Notifications (requests without an `id`, e.g. `notifications/initialized`) get `204 No Content`.

### Error codes

| Code     | Meaning                                              |
|----------|------------------------------------------------------|
| `-32700` | Parse error (malformed JSON)                         |
| `-32600` | Invalid request (not a valid JSON-RPC 2.0 object)    |
| `-32601` | Method not found                                     |
| `-32602` | Invalid params (bad arguments / unknown tool)        |
| `-32603` | Internal error                                       |
| `-32000` | Application error (e.g. record not found, job error) |

## Protocol methods

| Method                      | Purpose                                              |
|-----------------------------|------------------------------------------------------|
| `initialize`                | Handshake; returns protocol version and server info. |
| `ping`                      | Returns `{}`.                                        |
| `tools/list`                | Lists available tools with their JSON input schemas. |
| `tools/call`                | Invokes a tool by name with `arguments`.             |
| `notifications/initialized` | Notification; no response.                           |
| `notifications/cancelled`   | Notification; no response.                           |

### `tools/call` result shape

Tool results are returned in MCP's standard content envelope. The same structured payload appears twice — as pretty-printed JSON text and as `structuredContent`:

```json
{
  "content": [
    { "type": "text", "text": "{ ...pretty JSON... }" }
  ],
  "structuredContent": { "...": "..." },
  "isError": false
}
```

The per-tool payloads documented below are the contents of `structuredContent`.

## Tools

The server registers ten tools covering the marketing-agent loop end to end.

| Tool                  | Purpose                                                            |
|-----------------------|-------------------------------------------------------------------|
| `list_events`         | The "what should I post and where?" feed across all channels.     |
| `list_channels`       | All your channels with criteria, threshold, and event counts.     |
| `list_channel_events` | Events rated for one channel, ranked by relevance.                |
| `get_event`           | One event in full, with all ratings and linked-URL content.       |
| `search_events`       | Semantic (embedding) search over your events.                     |
| `mark_event_used`     | Mark an event as used in a channel.                               |
| `mark_event_unused`   | Undo a "used" mark.                                               |
| `add_manual_event`    | Add a manual event; extracts links and rates it.                  |
| `refresh_source`      | Enqueue re-ingestion of one source.                              |
| `rate_channel`        | Enqueue (re-)rating of a channel's events.                       |

Limits: most list tools cap `limit` at **200** (`search_events` caps at 50). Out-of-range integers are clamped, not rejected.

---

### `list_events`

The primary feed. Lists your recent events, each carrying the score and reason from **every** channel that has rated it — so a single call answers "what do I have, and where does it fit?"

**Arguments** (all optional):

| Name          | Type    | Default        | Notes                                                                             |
|---------------|---------|----------------|-----------------------------------------------------------------------------------|
| `since`       | string  | 7 days ago     | ISO8601. Only events published at or after this time.                              |
| `only_unused` | boolean | `true`         | Only events with at least one channel where `used=false`.                         |
| `min_score`   | integer | `0`            | 0–100. Only events with at least one channel rating ≥ this score.                  |
| `source_type` | string  | (no filter)    | One of `nostr`, `rss`, `manual`.                                                   |
| `event_type`  | string  | (no filter)    | One of `original`, `reply`, `repost`, `long_form`.                                 |
| `limit`       | integer | `50`           | 1–200.                                                                             |
| `offset`      | integer | `0`            | Pagination offset.                                                                 |

**Returns:** `{ events: [...], total_returned, offset, limit, since }`. Each event includes `id`, `source`, `event_type`, `external_id`, `source_link`, `published_at`, `content`, `content_resolved` (Nostr references resolved to plain text), `linked_urls`, and `channel_ratings[]` (`channel_id`, `channel_name`, `score`, `reason`, `used`, `used_at`).

---

### `list_channels`

Lists all marketing channels you own with their relevance criteria, threshold, and event counts.

**Arguments:** none.

**Returns:** `{ channels: [...] }`. Each channel: `id`, `name`, `description`, `language`, `prompt` (relevance criteria), `relevance_threshold`, `total_events`, `unused_events`, `used_events`.

---

### `list_channel_events`

Events rated for a specific channel, sorted by relevance score descending.

**Arguments:**

| Name          | Type    | Required | Default              | Notes                                   |
|---------------|---------|----------|----------------------|-----------------------------------------|
| `channel_id`  | integer | **yes**  | —                    | Channel to query.                       |
| `min_score`   | integer | no       | channel's threshold  | 0–100.                                   |
| `only_unused` | boolean | no       | `true`               | Only events not yet marked used.        |
| `limit`       | integer | no       | `50`                 | 1–200.                                   |
| `offset`      | integer | no       | `0`                  |                                         |

**Returns:** `{ channel, events: [...], total_returned, offset, limit }`.

---

### `get_event`

Fetch a single event in full: content, all per-channel ratings, and linked URLs with title/summary/excerpt where fetched.

**Arguments:**

| Name       | Type    | Required | Notes      |
|------------|---------|----------|------------|
| `event_id` | integer | **yes**  | Event ID.  |

**Returns:** `{ event, linked_contents: [{ url, title, fetched, summary, content_excerpt }] }`.

---

### `search_events`

Semantic search over your events using embeddings. Returns events ranked by similarity to the query.

**Arguments:**

| Name             | Type    | Required | Default | Notes                              |
|------------------|---------|----------|---------|------------------------------------|
| `query`          | string  | **yes**  | —       | Free-text query.                   |
| `limit`          | integer | no       | `10`    | 1–50.                              |
| `min_similarity` | number  | no       | `0.3`   | Cosine similarity floor, 0.0–1.0.  |

**Returns:** `{ events: [...], query }`. Each event includes a `similarity` score.

---

### `mark_event_used`

Mark an event as used in a specific channel (sets `used=true`, `used_at=now`).

**Arguments:**

| Name         | Type    | Required |
|--------------|---------|----------|
| `channel_id` | integer | **yes**  |
| `event_id`   | integer | **yes**  |

**Returns:** `{ ok: true, channel_event: {...} }`.

---

### `mark_event_unused`

Undo a "used" mark in a channel (clears `used` and `used_at`).

**Arguments:** same as `mark_event_used`.

**Returns:** `{ ok: true, channel_event: {...} }`.

---

### `add_manual_event`

Add a manual event to your manual source. Triggers link extraction and rates the new event against all channels.

**Arguments:**

| Name           | Type   | Required | Default | Notes                                          |
|----------------|--------|----------|---------|------------------------------------------------|
| `content`      | string | **yes**  | —       | Event content; URLs in it are extracted.       |
| `published_at` | string | no       | now     | ISO8601.                                        |

**Returns:** `{ ok: true, event: {...} }`. Ratings are computed asynchronously, so `channel_ratings` is empty in the immediate response — poll with `get_event` or `list_events`.

---

### `refresh_source`

Enqueue a background job to re-ingest a single source. Use sparingly — it fetches from Nostr relays or RSS.

**Arguments:**

| Name        | Type    | Required |
|-------------|---------|----------|
| `source_id` | integer | **yes**  |

**Returns:** `{ ok: true, source: {...}, enqueued: true }`.

---

### `rate_channel`

Enqueue a background job to (re-)rate events for a channel. Picks up unrated and recent events.

**Arguments:**

| Name         | Type    | Required |
|--------------|---------|----------|
| `channel_id` | integer | **yes**  |

**Returns:** `{ ok: true, channel: {...}, enqueued: true }`.

---

## Examples

### curl: list tools

```bash
curl -s https://lievik.cypherpunk.today/mcp \
  -H "Authorization: Bearer $LIEVIK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

### curl: the "what should I post and where?" feed

```bash
curl -s https://lievik.cypherpunk.today/mcp \
  -H "Authorization: Bearer $LIEVIK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "list_events",
      "arguments": { "since": "2026-05-01T00:00:00Z", "min_score": 60, "only_unused": true }
    }
  }'
```

### curl: mark an event used in a channel

```bash
curl -s https://lievik.cypherpunk.today/mcp \
  -H "Authorization: Bearer $LIEVIK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": { "name": "mark_event_used", "arguments": { "channel_id": 4, "event_id": 123 } }
  }'
```

### Connecting an MCP client

Any MCP client that speaks streamable HTTP can connect by pointing at the endpoint with a bearer token. Example client config:

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

For an agent-facing description of the project and the recommended workflow, see [`lievik-mcp-skill.md`](./lievik-mcp-skill.md).
