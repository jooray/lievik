# Lievik - Marketing Content Orchestrator

A web application designed to streamline and automate marketing content creation and distribution across multiple channels. Leverages AI agents (via CrewAI) to collect, process, evaluate, and help curate content, primarily sourced from Nostr feeds.

## Features

- Automated Content Ingestion from Nostr feeds
- AI-Powered Content Processing and Summarization  
- Channel Management with AI-driven content affinity scoring
- Multi-language support
- Content curation and reuse capabilities
- RAG-enabled content suggestions

## Technology Stack

- Backend: Python 3.11, Flask
- Frontend: Svelte
- Database: MySQL/PostgreSQL with SQLAlchemy
- AI: CrewAI for agent orchestration
- Content Processing: Trafilatura for web scraping
- Dependency Management: Poetry

## Getting Started

```bash
# Install dependencies
poetry install

# Setup environment
cp .env.example .env
# Edit .env with your configuration

# Initialize database
flask db init
flask db migrate -m "Initial migration"
flask db upgrade

# Run the application
flask run
```
