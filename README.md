# Lievik

**A Nostr-first content curation tool for creators who manage multiple audiences**

---

## What is Lievik?

Lievik helps you remember what content matters to which audience. If you create content across Nostr and the web, and communicate with different groups of people - newsletter subscribers, course students, community members - Lievik tracks what's relevant for each and what you've already shared with them.

### The Problem

You have multiple channels: a newsletter for your privacy course students, another for your Bitcoin meetup group, a Signal group for your open source project followers. You don't spam them - maybe you reach out once a month, or even once a year when something important happens.

But when it's time to write that email or post, you face the same questions:

- What have I created recently that's relevant for *this specific audience*?
- What did I already tell them about?
- There was that great thread I wrote three months ago - would they care about it? And will I remember I wrote it and should share it with them?
- I can't remember what I've shared with whom

The more channels you manage and the less frequently you contact them, the harder this gets.

### The Solution

Lievik watches your content sources (your Nostr posts, RSS feeds, accounts you follow) and helps you:

1. **Organize by channel** - Define what each audience cares about ("privacy tools", "Bitcoin development", "course updates")
2. **AI-powered relevance** - Automatically score every piece of content for each channel
3. **Track usage** - Know exactly what you've already used for each audience
4. **Build with AI** - Select relevant content and let AI help you craft polished updates

### Real Example

You run an online course. Once a year, you add a free bonus lesson and email your students. This is your one touchpoint - you want to maximize the value you deliver.

With Lievik, you:
1. Open your "Course Students" channel
2. See all your recent content scored by relevance to this audience
3. Filter out what you've already shared with them
4. Pick the best stuff and generate a polished email that announces the new lesson *and* includes other valuable content they haven't seen

No more "I think I already told them about this" or "I forgot I wrote that article they'd love."

## Who is this for?

- **Course creators** who email students with updates and bonus content
- **Newsletter writers** who curate from their own work and others'
- **Community managers** running multiple groups with different interests
- **Creators** who publish on Nostr and want to repurpose content for different audiences
- **Anyone** managing multiple communication channels who wants to deliver relevant value without repetition

## Nostr-First

Lievik is built for the Nostr ecosystem from the ground up:

- **Sign in with Nostr** - Use your browser extension (NIP-07) or remote signer like Amber (NIP-46). No passwords, no email signup.
- **Your npub is your identity** - Your Nostr profile picture and name, pulled from relays
- **Native content types** - Understands kind 1 notes, kind 30023 long-form articles, reposts
- **Proper linking** - Generates nevent/naddr identifiers with relay hints so links actually work

RSS feeds are supported too, but Nostr is home.

## How it Works

### 1. Add your sources

Connect Nostr accounts by npub - your own and others you follow. Add RSS feeds for web content. Lievik fetches everything automatically: short notes, long-form articles, reposts.

### 2. Create channels for your audiences

Each channel represents a group you communicate with:
- "Privacy Course Students"
- "Bitcoin Meetup Newsletter"
- "Open Source Project Updates"

Write a prompt describing what this audience cares about. The AI uses this to score incoming content.

### 3. Review and curate

Browse each channel sorted by relevance. High-scoring content rises to the top. See at a glance what you've already used. Filter to show only unused content.

### 4. Build your update

Select the pieces you want to include. Add a theme or direction ("this email is about the new lesson on VPNs"). Let AI weave them into polished copy. Edit with AI assistance ("make it shorter", "more casual tone"). Publish and mark the source content as used.

## Key Features

- **Multi-channel management** - Unlimited channels, each with its own relevance criteria
- **Usage tracking** - Never accidentally repeat content to the same audience
- **AI relevance scoring** - Each piece of content scored 0-100 for each channel
- **Content builder** - AI-assisted drafting with streaming generation
- **Version history** - Undo AI edits, restore previous versions
- **Link extraction** - Automatically fetches content from URLs in posts
- **Configurable templates** - Control how Nostr links appear in your content

## API / MCP Access

Lievik exposes its functionality to AI agents and scripts through a Model Context
Protocol (MCP) server at `POST /mcp` (JSON-RPC 2.0, authenticated with a personal
API token). Generate a token under **User settings → API Tokens**, then drive the
full curation loop — list events with per-channel ratings, search content, mark
items used, and more.

- Full reference: [`docs/API.md`](docs/API.md)
- Agent skill describing the project + workflow: [`docs/lievik-mcp-skill.md`](docs/lievik-mcp-skill.md)

## Tech Stack

- Ruby on Rails 8 with Hotwire (Turbo + Stimulus)
- SQLite (development) / MariaDB or MySQL (production)
- Tailwind CSS
- Solid Queue for background jobs
- OpenAI-compatible API for AI features (Venice, OpenAI, or any compatible endpoint)

## Try It Without Installing

A live instance runs at [lievik.cypherpunk.today](https://lievik.cypherpunk.today). Sign in with a Nostr browser extension (NIP-07) or remote signer (NIP-46) to try it with your own content — no installation required.

## Getting Started

```bash
# Clone the repo
git clone https://github.com/jooray/lievik.git
cd lievik

# Install dependencies
bundle install
yarn install

# Setup database
bin/rails db:create db:migrate

# Configure environment
cp .env.example .env
# Edit .env with your API keys

# Start the development server
bin/dev
```

### Configuration

Edit `config/lievik.yml` to configure:
- Nostr relays to connect to
- AI provider settings (endpoint, per-use-case models)

Set environment variables:
- `VENICE_API_KEY` or `OPENAI_API_KEY` for AI features

## Development

```bash
# Start all services (Rails, esbuild, Tailwind)
bin/dev

# Run migrations
bin/rails db:migrate

# Background jobs
bin/rails solid_queue:start

# Console
bin/rails console
```

## License

MIT — see [LICENSE](LICENSE).

---

*Lievik means "funnel" in Slovak - funneling the right content to the right audience.*
