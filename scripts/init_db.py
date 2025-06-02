#!/usr/bin/env python3
"""
Database initialization script for Lievik.
Creates tables and adds initial data.
"""

import os
import sys
import yaml

# Add the project root to the Python path
project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, project_root)

# Set the working directory to project root
os.chdir(project_root)

from lievik.app import create_app, db
from lievik.models import User, ChannelType, CrewConfiguration

def init_database():
    """Initialize the database with tables and initial data."""
    app = create_app()

    with app.app_context():
        print("Creating database tables...")
        db.create_all()

        # Check if initial data already exists
        if ChannelType.query.first() is not None:
            print("Database already initialized with data.")
            return

        print("Adding initial data...")

        # Create default crew configurations
        global_preprocessing_crew = CrewConfiguration(
            name="Global Content Preprocessing",
            is_global=True,
            config_yaml="""
# Global Content Preprocessing Crew
agents:
  - role: Web Scraper Agent
    goal: Fetch and extract clean text from URLs found in content
    backstory: An expert web content extractor with deep knowledge of web scraping
    tools: [ScrapeWebsiteTool]

  - role: Summarizer Agent
    goal: Create concise summaries of scraped web content
    backstory: A skilled content analyst who excels at distilling key information

  - role: Distance Evaluation Agent
    goal: Evaluate the actual distance of content based on user's projects and interests
    backstory: A personal content relevance analyst who understands user preferences

tasks:
  - description: Extract main content from web URLs
    agent: Web Scraper Agent

  - description: Generate summary of extracted content
    agent: Summarizer Agent

  - description: Calculate content relevance distance
    agent: Distance Evaluation Agent
"""
        )
        db.session.add(global_preprocessing_crew)

        channel_expert_crew = CrewConfiguration(
            name="Channel Expert",
            is_global=True,
            config_yaml="""
# Channel Expert Crew
agents:
  - role: Crew Customization Agent
    goal: Refine template CrewAI configurations based on user's channel descriptions
    backstory: An expert in designing AI teams for specific communication goals

tasks:
  - description: Customize crew configuration for channel
    agent: Crew Customization Agent
"""
        )
        db.session.add(channel_expert_crew)

        # Create default channel types
        newsletter_crew = CrewConfiguration(
            name="Newsletter Template",
            is_global=False,
            config_yaml="""
# Newsletter Channel Template
agents:
  - role: Relevance Assessment Agent
    goal: Score content relevance for this specific channel
    backstory: A specialist curator with deep understanding of the target audience

  - role: Language Acceptability Agent
    goal: Score language suitability for this channel
    backstory: A multilingual content compliance officer

  - role: Content Curation Agent
    goal: Select top relevant items for newsletter draft
    backstory: The meticulous chief editor for this newsletter

  - role: Copywriting Agent
    goal: Draft compelling newsletter sections from curated items
    backstory: A persuasive copywriter specializing in this topic and audience

tasks:
  - description: Assess content relevance
    agent: Relevance Assessment Agent

  - description: Check language acceptability
    agent: Language Acceptability Agent

  - description: Curate content for newsletter
    agent: Content Curation Agent

  - description: Write newsletter copy
    agent: Copywriting Agent
"""
        )
        db.session.add(newsletter_crew)

        signal_crew = CrewConfiguration(
            name="Signal Group Template",
            is_global=False,
            config_yaml="""
# Signal Group Channel Template
agents:
  - role: Relevance Assessment Agent
    goal: Score content relevance for this specific channel
    backstory: A specialist curator for social media engagement

  - role: Language Acceptability Agent
    goal: Score language suitability for this channel
    backstory: A multilingual content compliance officer

  - role: Post Formulation Agent
    goal: Create concise, engaging posts for the channel
    backstory: A social media engagement expert specializing in this topic

tasks:
  - description: Assess content relevance
    agent: Relevance Assessment Agent

  - description: Check language acceptability
    agent: Language Acceptability Agent

  - description: Formulate engaging post
    agent: Post Formulation Agent
"""
        )
        db.session.add(signal_crew)

        # Create Chat Reminder crew configuration from YAML
        chat_reminder_crew_config_path = os.path.join(project_root, 'lievik', 'core', 'seed_data', 'chat_reminder_crew_config.yaml')
        try:
            with open(chat_reminder_crew_config_path, 'r') as f:
                chat_reminder_yaml_content = f.read()

            chat_reminder_crew = CrewConfiguration(
                name="Chat Reminder Template",
                is_global=False,
                config_yaml=chat_reminder_yaml_content
            )
            db.session.add(chat_reminder_crew)
            print("Added Chat Reminder Crew Configuration.")
        except FileNotFoundError:
            print(f"ERROR: chat_reminder_crew_config.yaml not found at {chat_reminder_crew_config_path}", file=sys.stderr)
        except Exception as e:
            print(f"ERROR: Could not load or create Chat Reminder Crew Configuration: {e}", file=sys.stderr)

        # Commit crews first so we can reference them
        db.session.commit()

        # Create channel types
        newsletter_type = ChannelType(
            name="Course Newsletter",
            description="Educational newsletter for course participants",
            default_crew_configuration_id=newsletter_crew.id
        )
        db.session.add(newsletter_type)

        signal_type = ChannelType(
            name="Signal Group",
            description="Signal group for community discussions and content sharing",
            default_crew_configuration_id=signal_crew.id
        )
        db.session.add(signal_type)

        social_type = ChannelType(
            name="Social Media",
            description="General social media posting",
            default_crew_configuration_id=signal_crew.id
        )
        db.session.add(social_type)

        # Create Chat Reminder ChannelType if its crew was loaded
        chat_reminder_crew_from_db = CrewConfiguration.query.filter_by(name="Chat Reminder Template").first()
        if chat_reminder_crew_from_db:
            chat_reminder_channel_type = ChannelType(
                name="Chat Reminder",
                description="Channel for sending chat-based reminders and notifications.",
                default_crew_configuration_id=chat_reminder_crew_from_db.id
            )
            db.session.add(chat_reminder_channel_type)
            print("Added Chat Reminder Channel Type.")
        else:
            print("Skipped creating Chat Reminder Channel Type because its crew configuration was not found or not committed.", file=sys.stderr)

        # Create a default user for development
        default_user = User(
            username="admin",
            email="admin@lievik.local",
            password_hash="placeholder-hash"  # TODO: Implement proper password hashing
        )
        db.session.add(default_user)

        db.session.commit()
        print("Database initialized successfully!")

        # Print summary
        print(f"\nCreated:")
        print(f"- {CrewConfiguration.query.count()} crew configurations")
        print(f"- {ChannelType.query.count()} channel types")
        print(f"- {User.query.count()} users")


if __name__ == '__main__':
    init_database()
