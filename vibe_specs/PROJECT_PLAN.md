## Project Plan: "Lievik" - MVP (Chat Reminders)

This plan outlines the steps to develop the Minimum Viable Product (MVP) for Lievik, focusing on the "chat reminder" channel type with Nostr as the primary data source.

**Phase 1: Core Backend & Data Model Setup**

*   **Task 1.1: Project Setup & Initial Database Schema**
    *   **Role:** Backend Developer (Python), Database Specialist
    *   **Task:**
        *   Initialize Python project with Poetry.
        *   Set up Flask application structure.
        *   Define initial SQLAlchemy models for: `Users`, `Sources`, `ContentItems`, `ProcessedWebContent`, `Channels`, `ChannelTypes`, `CrewConfigurations`, `ChannelContentAffinity`, `Notifications`, `ChannelNotifications`. (Refer to ARCHITECTURE.md section 3.3).
        *   Configure database connection (MySQL/PostgreSQL).
        *   Create initial database migration scripts.
    *   **Goal:** A runnable Flask application connected to a database with the core tables created. Basic user model for future authentication.

*   **Task 1.2: Basic User Authentication**
    *   **Role:** Backend Developer (Python)
    *   **Task:** Implement simple email/password-based user registration and login.
    *   **Goal:** Users can create accounts and log in. Subsequent entities will be associated with a `user_id`.

*   **Task 1.3: LLM API Configuration**
    *   **Role:** Backend Developer (Python), CrewAI Specialist
    *   **Task:**
        *   Implement a configuration mechanism (e.g., environment variables, config file) for LLM API keys (`GEMINI_API_KEY`, `VENICE_API_KEY`, etc.) and endpoints (Ollama).
        *   Ensure CrewAI telemetry is disabled (`CREWAI_DISABLE_TELEMETRY = 'true'`, `OTEL_SDK_DISABLED = 'true'`).
    *   **Goal:** The application can be configured to use different LLM providers.

**Phase 2: Content Ingestion Daemon**

*   **Task 2.1: Nostr Data Fetching**
    *   **Role:** Backend Developer (Python)
    *   **Task:**
        *   Implement a script/module using `nostr-sdk` to fetch events from a configurable list of Nostr `npubs` and relays.
        *   Store raw event data, link URLs, and publication dates into the `ContentItems` table, associated with a `Source`.
    *   **Goal:** Daemon can connect to Nostr, fetch events for specified `npubs`, and store them.

*   **Task 2.2: Web Content Parsing**
    *   **Role:** Backend Developer (Python)
    *   **Task:** Integrate `trafilatura` to extract main content, title from URLs found in Nostr events. Store this in `ProcessedWebContent`.
    *   **Goal:** Linked web pages are parsed, and their content is stored.

*   **Task 2.3: Global Content Preprocessing Crew - Initial Setup**
    *   **Role:** CrewAI Specialist, Backend Developer (Python)
    *   **Task:**
        *   Define the initial YAML configuration for the "Global Content Preprocessing Crew" (Web Scraper Agent, Summarizer Agent, Distance Evaluation Agent - as per ARCHITECTURE.md 5.1). Store this in a seed file.
        *   Implement logic to load this default global crew configuration into the `CrewConfigurations` table on first app setup.
        *   Develop the core logic for these agents:
            *   Summarizer Agent: Basic LLM call to summarize text.
            *   Distance Evaluation Agent: Takes user's free-text description of projects/websites (from a placeholder user setting for now) and content details to estimate "actual distance" using an LLM.
    *   **Goal:** A basic Global Content Preprocessing Crew can be instantiated and its agents can perform their core tasks (summarization, initial distance evaluation).

*   **Task 2.4: Daemon Main Loop & Scheduling**
    *   **Role:** Backend Developer (Python)
    *   **Task:**
        *   Structure the daemon to:
            1.  Fetch new Nostr events.
            2.  For each event, parse links (if any).
            3.  Execute the Global Content Preprocessing Crew (summarization, actual distance evaluation, initial language detection - can be a simple placeholder for now).
            4.  Store `ContentItems` and `ProcessedWebContent`.
        *   Set up basic scheduling (e.g., a cron job or a simple loop for development).
    *   **Goal:** The daemon can run periodically, ingest Nostr content, perform initial processing, and store results in the database.

**Phase 3: Channel Management & Per-Channel Evaluation (MVP Focus)**

*   **Task 3.1: Channel and Channel Type Management - Backend**
    *   **Role:** Backend Developer (Python)
    *   **Task:**
        *   Implement Flask API endpoints for CRUD operations on `Channels` and `ChannelTypes`.
        *   A `Channel` will include `name`, `user_id`, `language`, `channel_type_id`, `crew_configuration_id`.
        *   A `ChannelType` will include `name` and `default_crew_configuration_id`.
        *   Define the initial YAML for a "Chat Reminder" `ChannelType` and its default per-channel crew configuration (Relevance Agent, Language Agent, Post Formulation Agent - as per ARCHITECTURE.md 5.2). Store in a seed file.
        *   Implement logic to load this default channel type and its crew config into the DB on first setup.
    *   **Goal:** Backend logic to manage channels and their types, including their associated default crew configurations.

*   **Task 3.2: Per-Channel Crew Execution Logic**
    *   **Role:** CrewAI Specialist, Backend Developer (Python)
    *   **Task:**
        *   Extend the daemon: After a `ContentItem` is processed by the Global Preprocessing Crew, iterate through all active `Channels` for the user.
        *   For each `Channel`, load its specific `CrewConfiguration`.
        *   Instantiate and run the channel's crew:
            *   **Relevance Assessment Agent:** Basic LLM call using channel description (placeholder for now) and content summary to score relevance.
            *   **Language Acceptability Agent:** Basic logic/LLM call to assess language suitability based on channel language and content language.
            *   **(Reminder) Post Formulation Agent:** Basic LLM call to generate a short post suggestion based on content.
        *   Calculate and store `final_affinity_score` in `ChannelContentAffinity`.
        *   If affinity for a "Chat Reminder" channel exceeds a threshold, create a `Notification` record (message can be the output of Post Formulation Agent). Link it via `ChannelNotifications`.
    *   **Goal:** New content is evaluated against each channel, affinity scores are stored, and notifications are generated for relevant items in "Chat Reminder" channels.

**Phase 4: Web Application Frontend (Svelte - MVP Focus)**

*   **Task 4.1: Basic Frontend Setup & User Authentication UI**
    *   **Role:** Frontend Developer (Svelte), Designer
    *   **Task:**
        *   Set up Svelte project structure.
        *   Implement UI components for user registration and login, connecting to backend APIs.
        *   Basic navigation and layout.
    *   **Goal:** Users can register and log in via the web interface.

*   **Task 4.2: Nostr Source Configuration UI**
    *   **Role:** Frontend Developer (Svelte), Designer
    *   **Task:**
        *   UI for users to add/edit/delete Nostr `Sources` (`npub`, relays, `base_distance`).
        *   A text area for the user to input their free-text description of projects/websites (for the Distance Evaluation Agent).
        *   Connect to backend APIs for `Sources`.
    *   **Goal:** Users can configure their Nostr data sources and provide context for distance evaluation.

*   **Task 4.3: Channel Management UI (MVP - Chat Reminders)**
    *   **Role:** Frontend Developer (Svelte), Designer
    *   **Task:**
        *   UI to list existing channels.
        *   UI to create a new channel:
            *   User provides `name`, selects "Chat Reminder" `ChannelType` (MVP only offers this type), sets `language`.
            *   User provides a textual description for the channel (purpose, audience - for the Relevance Agent).
            *   (For MVP, the default crew from the "Chat Reminder" type is used directly; LLM-based crew customization and YAML editing will be deferred).
        *   Connect to backend APIs for `Channels`.
    *   **Goal:** Users can create and view "Chat Reminder" channels.

*   **Task 4.4: Notification Display UI (MVP)**
    *   **Role:** Frontend Developer (Svelte), Designer
    *   **Task:**
        *   Create a view (e.g., integrated into a channel dashboard or a separate notifications page) to display pending notifications for "Chat Reminder" channels.
        *   Each notification card should show:
            *   Snippet of the original content.
            *   Source (e.g., npub) with a link to the original content (e.g., njump.me).
            *   Suggested post text generated by the Post Formulation Agent.
            *   Channels this notification pertains to (if grouped).
        *   Implement actions: "Mark as Processed," "Copy Post Text."
        *   Connect to backend APIs for fetching and updating notifications.
    *   **Goal:** Users can see suggested posts for their chat reminder channels and take basic actions.

**Phase 5: Integration, Testing & Refinement**

*   **Task 5.1: End-to-End Testing (MVP Flow)**
    *   **Role:** All Developers, QA
    *   **Task:**
        *   Test the complete flow:
            1.  User configures Nostr source.
            2.  User creates a "Chat Reminder" channel.
            3.  Daemon runs, ingests content, processes it.
            4.  Content is evaluated against the channel.
            5.  Notification appears in the UI.
            6.  User interacts with the notification.
    *   **Goal:** The MVP workflow is functional and stable.

*   **Task 5.2: Basic Crew Configuration UI (View/Edit Global Crews - Stretch for MVP)**
    *   **Role:** Frontend Developer (Svelte), Backend Developer (Python)
    *   **Task:**
        *   (If time permits) A simple admin UI to view/edit the YAML for Global `CrewConfigurations` (e.g., Content Preprocessing Crew).
    *   **Goal:** Admins can inspect and tweak global crew behaviors.

*   **Task 5.3: Documentation & Deployment Preparation**
    *   **Role:** All Developers
    *   **Task:**
        *   Basic README update.
        *   Prepare deployment scripts/notes (e.g., for Docker).
    *   **Goal:** Project is ready for initial deployment and use.

This plan prioritizes getting the core "chat reminder" flow operational. Subsequent iterations will build upon this foundation to add newsletter functionality, RAG, advanced crew customization, and other features outlined in the full architecture.
