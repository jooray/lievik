Okay, here's a summary report of our discussion and the key decisions made for the "Lievik" project:

## Project "Lievik" - Customer Meeting Summary

**Objective:** To create a web application for personal marketing content creation, leveraging Nostr feeds (and potentially other sources) and AI agents (CrewAI) for content processing, evaluation, and curation across various marketing channels.

**Key Decisions & Information Gathered:**

1.  **Content Ingestion & Initial Processing (Daemon):**
    *   A daemon will collect content (initially Nostr, extensible to RSS, etc.) hourly or daily.
    *   "Distance" for Nostr sources is initially tied to the `npub`.
    *   The daemon will perform significant preprocessing using a **Global Content Preprocessing Crew**:
        *   Fetch and parse linked web pages (`trafilatura`).
        *   Generate LLM-based summaries.
        *   Store full text, summary, title, and original URL (web content stored separately and reused if linked multiple times).
        *   An AI agent will evaluate the "actual distance" of content by considering the user's predefined projects/websites, adjusting the source's base distance.
        *   Detect initial language.
    *   Each ingested item will include source type (nostr, rss), source identifier (npub, feed URL), and specific content link (nevent, article URL).

2.  **Channel & CrewAI Management:**
    *   Users will create "channels" (e.g., newsletters, social media group reminders) via a web interface.
    *   Channels have types (e.g., "Course Newsletter") which provide default CrewAI configurations (agents, tasks, backstories).
    *   When creating a channel, users describe its purpose and audience. A **Global "Channel Expert" Crew** will use this description to customize the template crew configuration (YAML). Users can then view, edit (via YAML editor or further LLM prompts), and confirm this per-channel crew.
    *   Per-channel crew configurations will be stored as YAML in the database.
    *   Global crew configurations (like the Preprocessing Crew or Channel Expert Crew) will also be stored as YAML in the database and editable via a similar interface.
    *   Users will primarily edit crew goals, backstories, and tasks. Available tools will be managed via a central configuration.

3.  **Content Evaluation & Affinity:**
    *   For each new content item processed by the daemon, it will be evaluated against *every active channel*.
    *   Each channel's specific CrewAI crew will run, typically including:
        *   **Relevance Assessment Agent:** Scores relevance based on the channel's description, target persona, and the content itself (including any linked web content).
        *   **Language Acceptability Agent:** Scores if the content's language is appropriate for the channel (e.g., SK/CZ content acceptable for SK channels; EN less so; EN-only for EN channels). This is channel-specific.
    *   The final affinity score will combine relevance, language, and the "actual distance" (lower distance is better).
    *   This evaluation happens continuously as content is ingested.

4.  **Web Interface & User Interaction:**
    *   **Dashboard:** Display channels (name, type, language, icon, pending items/notifications), with filtering and search.
    *   **Channel View:** Show content items with high affinity for that channel.
    *   **Notifications:** For "reminder" type channels (e.g., Signal groups), if content affinity exceeds a threshold, an internal notification is generated. Notifications are grouped if one item is relevant to multiple channels. A "mark as processed" feature will be available.
    *   **Newsletter Composing:**
        *   Suggests top N unprocessed, high-affinity content items.
        *   Users select, edit (using a rich Markdown editor like Toast UI Editor), and save content as reusable "Stories."
        *   "Stories" are stored with their language explicitly set.
        *   **RAG:** After saving a "Story," the system will search a vector store (containing all ingested content and past stories) for relevant past items and suggest them as additional blocks.
        *   Saved "Stories" are available for other newsletters. If a story's language differs from the target newsletter's language, it will be automatically pre-translated (or translated on-the-fly).

5.  **Technology Choices:**
    *   **Backend:** Python 3.11, Flask.
    *   **Frontend:** Svelte.
    *   **Database:** SQL (MySQL/PostgreSQL) with SQLAlchemy.
    *   **AI:** CrewAI.
    *   **LLM APIs:** Configurable (Ollama, Venice API, OpenAI-compatible), with ability to specify different models per agent. Telemetry disabled.
    *   **Nostr:** `nostr-sdk`.
    *   **Web Parsing:** `trafilatura`.
    *   **Dependencies:** Poetry.

This summary captures the core requirements and decisions that will guide the architecture and development.
