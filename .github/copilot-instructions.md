# Lievik - Copilot Instructions

## Architecture Overview

Lievik is a **Rails 8.1 content curation app** that ingests Nostr events, rates them with AI, and organizes content for marketing channels.

**Data flow:** Sources (Nostr/RSS) → Events → AI Rating → ChannelEvents (scored per channel) → Used/Unused tracking

**Key relationships:**
- `User` → owns `Sources`, `Channels`
- `Source` → produces `Events` (via ingestion services)
- `Channel` → has `ChannelEvents` (join table with `relevance_score`)
- `Event` → can appear in multiple channels with different scores

## Essential Commands

```bash
bin/dev                          # Start all services (Rails, esbuild, Tailwind, Solid Queue)
bin/rails solid_queue:start      # Run background jobs separately
yarn build && yarn build:css     # Rebuild assets manually
```

## Ruby Environment

**IMPORTANT:** This project uses Homebrew Ruby. Always set PATH before running commands:

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
```

Or prefix terminal commands with the export inline:
```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH" && bin/rails db:migrate
```

## Service Layer Patterns

Services live in `app/services/` organized by domain:

- **`Ai::Client`** - OpenAI-compatible HTTP client (VeniceAI default)
- **`Ai::RatingService`** - Scores events 0-100 against channel prompts
- **`Ingestion::NostrIngestionService`** - Fetches Nostr events via relays
- **`Nostr::AuthService`** - NIP-07/NIP-46 authentication

Services accept `activity_log_id:` for operation tracking with `DevLog` entries.

## Configuration

App config in `config/lievik.yml` (Nostr relays, AI settings). Access via:
```ruby
Rails.application.config_for(:lievik).dig(:ai, :models, :classification)
```

Environment variables: `VENICE_API_KEY` or `OPENAI_API_KEY`

## Model Conventions

- **JSON settings columns**: Models use `settings` JSON for flexible config (see `Source.settings`, `Channel.settings`)
- **Virtual accessors**: `settings_include_replies=` pattern for form binding
- **Enums**: Use Rails enums (`source_type`, `event_type`)
- **Default settings**: `after_initialize :set_default_settings, if: :new_record?`

## Background Jobs (Solid Queue)

Jobs in `app/jobs/` follow this pattern:
```ruby
activity_log = ActivityLog.start_activity(user:, activity_type:, message:)
# ... do work ...
activity_log.complete!(message:) # or activity_log.fail!(message:)
```

Key jobs: `SourceIngestionJob`, `RateEventsJob`, `RefreshAllSourcesJob`

## Frontend Stack

- **Hotwire**: Turbo + Stimulus for interactivity
- **Tailwind CSS 4.x**: Dark mode via `dark:` variants
- **Stimulus controllers** in `app/javascript/controllers/`:
  - `nostr_login_controller.js` - NIP-07 browser extension detection
  - `theme_controller.js` - Dark mode toggle
  - `markdown_editor_controller.js` - EasyMDE integration

## Authentication

Nostr-only auth via:
1. **NIP-07**: Browser extension (`window.nostr`)
2. **NIP-46**: QR code + relay communication (`nostrconnect://` URI)

Session stored in Rails session with `session[:user_id]`. Auth helper: `current_user`, `user_signed_in?`

## Testing & Quality

```bash
bin/rubocop         # Ruby linting
bin/brakeman        # Security scanning
bin/bundler-audit   # Dependency vulnerabilities
```

## Key Files Reference

- [config/lievik.yml](config/lievik.yml) - App configuration
- [config/routes.rb](config/routes.rb) - All routes including nested resources
- [app/services/ai/rating_service.rb](app/services/ai/rating_service.rb) - AI scoring logic
- [app/jobs/source_ingestion_job.rb](app/jobs/source_ingestion_job.rb) - Background ingestion pattern
