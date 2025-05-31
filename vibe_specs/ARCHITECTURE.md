## Software Architecture Specification: "Lievik" Marketing Content Orchestrator

### 1. Overview

Lievik is a web application designed to streamline and automate marketing content creation and distribution across multiple channels. It leverages AI agents (via CrewAI) to collect, process, evaluate, and help curate content, primarily sourced from Nostr feeds (and extensible to other sources like RSS). The system supports personalized content workflows, multi-language content, and varying channel interaction patterns (proactive reminders vs. user-initiated creation).

### 2. Key Features

*   **Automated Content Ingestion:** Daemon to collect Nostr events and parse linked web content.
*   **AI-Powered Content Processing:**
    *   Summarization of web articles.
    *   Dynamic "distance" evaluation based on user's projects and relationships.
    *   Language detection and acceptability assessment.
*   **Channel Management:**
    *   Creation and configuration of diverse marketing channels (newsletters, social media reminders).
    *   Channel types with pre-filled, editable CrewAI configurations.
    *   LLM-assisted customization of channel crews.
    *   Per-channel language settings.
*   **Content Affinity Scoring:** AI agents evaluate content relevance for each channel.
*   **Web Interface:**
    *   Dashboard for channel overview and pending content/notifications.
    *   Newsletter composing interface with Markdown editor and RAG features.
    *   Management of global and per-channel CrewAI configurations.
    *   User authentication.
*   **Content Curation & Reuse:**
    *   Saving edited content as reusable "Stories."
    *   Automatic translation of "Stories" for different language channels.
    *   RAG for suggesting relevant past content during newsletter composition.
*   **Flexible CrewAI Integration:**
    *   Support for global and per-channel crews.
    *   Configurable LLM inference APIs (Ollama, Venice API, custom models per agent).
*   **Notification System:** Internal web app notifications for channels requiring proactive posting.

### 3. System Architecture

#### 3.1. High-Level Components

1.  **Content Ingestion Daemon:** A background process responsible for fetching, parsing, and performing initial AI-driven preprocessing of content.
2.  **Web Application:** Flask backend serving a Svelte frontend, providing the user interface for channel management, content curation, and system configuration.
3.  **Database:** SQL database (MySQL or PostgreSQL) storing all persistent data, including content, channel configurations, user data, and AI crew configurations.
4.  **CrewAI Engine:** Integrated within both the daemon and web application backend to execute AI agent tasks.
5.  **Vector Store:** For enabling RAG capabilities, storing embeddings of content and stories.

#### 3.2. Technology Stack

*   **Backend:** Python 3.11, Flask
*   **Frontend:** Svelte
*   **Database:** SQLAlchemy (for MySQL/PostgreSQL abstraction)
*   **AI Orchestration:** CrewAI
*   **Nostr Integration:** `nostr-sdk` (Python)
*   **Web Content Parsing:** `trafilatura`
*   **Dependency Management:** Poetry
*   **LLM APIs:** Configurable (Ollama, Venice API, OpenAI-compatible)
*   **Vector Store:** To be chosen (e.g., FAISS, ChromaDB, or `pgvector` if using PostgreSQL).
*   **Markdown Editor:** Toast UI Editor 

#### 3.3. Core Database Schema (Conceptual)

*   **`Sources`**: (e.g., Nostr npubs, RSS feed URLs)
    *   `id`, `type` (nostr, rss), `identifier` (npub, url), `base_distance`, `user_id`
*   **`ContentItems`**: (Raw ingested content)
    *   `id`, `source_id` (FK), `original_id_on_source` (e.g., Nostr event ID), `raw_content`, `link_url`, `publication_date`, `initial_distance` (from source), `language_detected`
*   **`ProcessedWebContent`**: (Scraped and summarized web pages)
    *   `id`, `original_url` (unique), `title`, `full_text`, `summary_text`, `processing_date`
    *   (A `ContentItem` can link to a `ProcessedWebContent` if it contains a URL)
*   **`Channels`**:
    *   `id`, `user_id`, `name`, `description_by_user`, `target_persona`, `channel_type_id` (FK to `ChannelTypes`), `language` (e.g., 'en', 'sk'), `crew_configuration_id` (FK to `CrewConfigurations`), `icon_url`
*   **`ChannelTypes`**: (Templates for channels)
    *   `id`, `name` (e.g., "Course Newsletter", "Signal Group"), `default_crew_configuration_id` (FK to `CrewConfigurations`)
*   **`CrewConfigurations`**: (Stores YAML/JSON for CrewAI setups)
    *   `id`, `name` (e.g., "Global Preprocessing", "Channel X Main Crew"), `config_yaml`, `is_global` (boolean)
*   **`Stories`**: (User-curated and edited content blocks for reuse)
    *   `id`, `user_id`, `original_content_item_id` (FK, optional), `title`, `body_markdown`, `language`, `created_at`, `last_edited_at`, `source_channel_id` (FK, optional - where it was first curated)
*   **`TranslatedStories`**:
    *   `id`, `original_story_id` (FK), `language`, `translated_title`, `translated_body_markdown`
*   **`ChannelContentAffinity`**: (Stores evaluation results)
    *   `id`, `content_item_id` (FK), `channel_id` (FK), `relevance_score`, `language_acceptability_score`, `final_affinity_score`, `status` (e.g., 'new', 'suggested', 'processed_for_newsletter_X')
*   **`Notifications`**:
    *   `id`, `user_id`, `content_item_id` (FK), `message`, `created_at`, `is_processed`
*   **`ChannelNotifications`**: (Links a notification to multiple relevant channels)
    *   `notification_id` (FK), `channel_id` (FK)
*   **`Users`**: Basic user authentication fields.

### 4. Core Modules & Components

#### 4.1. Content Ingestion Daemon

*   **Responsibilities:**
    *   Periodically fetch new events from configured Nostr sources (npubs). (Extensible for RSS etc.)
    *   For events with links, use `trafilatura` to extract main content from URLs.
    *   Execute a **Global Content Preprocessing Crew** for each new item:
        *   Generate an LLM-based summary of scraped web content.
        *   Determine "actual distance" (evaluating if content relates to user's defined projects/websites, adjusting `base_distance` from source).
        *   Detect initial language of the content.
    *   Store raw `ContentItems` and `ProcessedWebContent` in the database.
    *   Trigger per-channel evaluation for each new, processed `ContentItem`.
*   **Scheduling:** Cron job (e.g., hourly or daily).

#### 4.2. Per-Channel Content Evaluation

*   **Trigger:** Invoked by the Ingestion Daemon for each new `ContentItem`.
*   **Process:**
    1.  For the given `ContentItem`, iterate through all active `Channels` defined by the user.
    2.  For each `Channel`:
        *   Load its specific `CrewConfiguration` (YAML/JSON).
        *   Instantiate and run the channel's CrewAI crew. This crew will typically include:
            *   **Relevance Assessment Agent:** Evaluates content relevance based on channel description, persona, content summary, etc.
            *   **Language Acceptability Agent:** Assesses if content language is suitable for the channel, applying scoring adjustments (e.g., SK/CZ fine, EN for SK channel less fine).
        *   Calculate a final `final_affinity_score` (combining relevance, language, distance).
        *   Store this score in `ChannelContentAffinity`.
    3.  If the `final_affinity_score` for a "reminder" type channel exceeds a defined threshold, generate a `Notification`.

#### 4.3. Web Application (Flask Backend & Svelte Frontend)

*   **User Authentication:** Basic login/registration.
*   **Channel Management:**
    *   UI to CRUD `Channels`.
    *   Users select a `ChannelType` (e.g., "Course Newsletter") to get a default `CrewConfiguration`.
    *   Users provide a textual description of the channel and its purpose/audience.
    *   A **Global "Channel Expert" Crew** takes this description and the template crew config to suggest a customized `CrewConfiguration` (YAML).
    *   User can view, edit (via YAML editor and/or further LLM-based refinement prompts), and confirm the crew config.
    *   Channel dashboard: List channels with name, type, language, icon, count of pending items/notifications. Filter by type, text search.
*   **Content Display & Interaction:**
    *   Per-channel views showing `ContentItems` with high `final_affinity_score`.
    *   Notification center: Display grouped notifications (one card for an item relevant to multiple channels), "Mark all as processed" button.
*   **Newsletter Composing Interface:**
    *   When creating/editing a newsletter for a channel:
        *   Suggests `ContentItems` (not yet used in this newsletter series) with high affinity for this channel (Top N).
        *   User selects items with checkboxes.
        *   Selected items can be edited in a Markdown editor (e.g., Toast UI Editor).
        *   Edited content is saved as a `Story` (Markdown, language explicitly set).
        *   **RAG:** After a user saves a `Story` block, the system searches the vector store (containing all `ProcessedWebContent` and existing `Stories`) for highly relevant past items and suggests them as additional blocks to incorporate/adapt. Suggestions are full stories/content, easy to copy.
        *   If a `Story` (e.g., in Slovak) is selected for a newsletter in a different language (e.g., English), the system uses its pre-translated version (from `TranslatedStories`) or triggers on-the-fly translation via an LLM agent if not yet translated. Pre-translation of saved stories is preferred.
    *   Output is copyable Markdown, rendered as HTML in the UI.
*   **Global Crew Configuration Management:**
    *   Admin interface to view/edit YAML for global `CrewConfigurations` (e.g., Content Preprocessing Crew, Channel Expert Crew).

#### 4.4. CrewAI Integration

*   **Configuration Storage:** `CrewConfigurations` (YAML/JSON) stored in the database.
*   **Execution:** Dynamically load and instantiate crews from stored configurations.
*   **LLM Flexibility:**
    *   System-wide default LLM (e.g., from Venice API, Ollama).
    *   Allow specifying different LLMs/APIs per agent within a crew configuration.
    *   `GEMINI_API_KEY`, `VENICE_API_KEY` managed via environment variables.
    *   Telemetry disabled: `CREWAI_DISABLE_TELEMETRY = 'true'`, `OTEL_SDK_DISABLED = 'true'`.
*   **Standard Tools:** `ScrapeWebsiteTool`. Custom tools as needed (e.g., for translation, database lookups).

#### 4.5. Database & RAG

*   **ORM:** SQLAlchemy.
*   **Vector Store Integration:**
    *   Embeddings generated for `ProcessedWebContent` (summaries, full text) and `Stories`.
    *   Vector store queried during newsletter composition (RAG) to find relevant past content.

### 5. CrewAI Agent Design (Examples)

#### 5.1. Global Crews

1.  **Content Preprocessing Crew:**
    *   **Web Scraper Agent:**
        *   Goal: Fetch and extract clean text from URLs found in content.
        *   Tool: `ScrapeWebsiteTool`, `trafilatura`.
        *   Backstory: An expert web content extractor.
    *   **Summarizer Agent:**
        *   Goal: Create concise summaries of scraped web content.
        *   Tool: LLM.
        *   Backstory: A skilled content analyst.
    *   **Distance Evaluation Agent:**
        *   Goal: Evaluate the "actual distance" of content based on user's predefined projects, websites, and the source's base distance.
        *   Context: User's list of projects/sites (from config/DB).
        *   Tool: LLM (for semantic understanding if needed), simple logic.
        *   Backstory: A personal content relevance analyst.

2.  **Channel Expert Crew:**
    *   **Crew Customization Agent:**
        *   Goal: Refine a template CrewAI configuration based on user's natural language description of a channel.
        *   Context: Channel template YAML, user's channel description, target persona.
        *   Tool: LLM.
        *   Backstory: An expert in designing AI teams for specific communication goals.

#### 5.2. Per-Channel Crew (Template Examples - customized per channel)

1.  **Relevance Assessment Agent:**
    *   Goal: Score content relevance for *this specific channel*.
    *   Context: Channel description, target persona, content summary, link, actual distance.
    *   Tool: LLM.
    *   Backstory: A specialist curator for [Channel Topic/Audience].
2.  **Language Acceptability Agent:**
    *   Goal: Score language suitability for *this channel*, applying penalties.
    *   Context: Channel language, content language, rules (e.g., SK/CZ = 1.0, SK content for EN channel = 0.2).
    *   Tool: LLM (for nuanced understanding if needed), rule-based logic.
    *   Backstory: A multilingual content compliance officer for [Channel Language].
3.  **(Newsletter) Content Curation Agent:** (If channel type is newsletter)
    *   Goal: Select top N unprocessed, relevant items for the newsletter draft.
    *   Tool: Database access (to check `ChannelContentAffinity` and processing status).
    *   Backstory: The meticulous chief editor for the [Channel Name] newsletter.
4.  **(Newsletter) Copywriting Agent:** (If channel type is newsletter)
    *   Goal: Draft compelling newsletter sections from curated items, in the channel's language.
    *   Tool: LLM, Translation Tool (if a selected `Story` needs ad-hoc translation).
    *   Backstory: A persuasive copywriter for [Channel Topic/Audience] in [Channel Language].
5.  **(Reminder) Post Formulation Agent:** (If channel type is reminder-based, e.g., Signal)
    *   Goal: Create a concise, engaging post (text + link) for the channel.
    *   Tool: LLM.
    *   Backstory: A social media engagement expert specializing in [Channel Topic].

### 6. Data Flow Examples

#### 6.1. New Content Item Ingestion & Evaluation

1.  Daemon fetches Nostr event.
2.  If link present, Scraper Agent (Global Preprocessing Crew) fetches and cleans web page.
3.  Summarizer Agent (Global) summarizes.
4.  Distance Agent (Global) calculates actual distance.
5.  ContentItem and ProcessedWebContent stored.
6.  For each active Channel:
    *   Channel's crew (Relevance Agent, Language Agent) runs.
    *   Affinity score calculated and stored.
    *   If reminder channel & high affinity, Notification created.

#### 6.2. Newsletter Creation

1.  User selects "Create Newsletter" for a channel.
2.  UI shows suggested `ContentItems` (high affinity, unprocessed for this newsletter series).
3.  User selects items, edits them in Markdown editor, saves as `Stories`.
4.  For each saved `Story`, RAG triggers: system searches vector store for related past `Stories`/`ProcessedWebContent`.
5.  Suggestions displayed; user can incorporate them.
6.  If a `Story` from another language is used, it's translated (ideally pre-translated).
7.  Final newsletter compiled by Copywriting Agent (part of channel's crew or a general newsletter crew).
8.  Output is Markdown.

### 7. Future Considerations

*   **Performance Optimization:** For per-channel crew executions (batching, caching, lighter pre-filtering).
*   **Advanced RAG:** Real-time suggestions in editor, more sophisticated query understanding.
*   **Expanded Content Sources:** Formalize integration for RSS, etc.
*   **Advanced Analytics:** Track content performance across channels.

This specification should provide a solid foundation for the development team.
