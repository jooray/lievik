#!/usr/bin/env python3
"""
Script to display all ingested Nostr events.

This script queries the database for all ContentItem records that come from Nostr sources
and displays them in a readable format.
"""

import sys
import os

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lievik.app import create_app, db
from lievik.models import ContentItem, Source, ProcessedWebContent
from datetime import datetime


def display_nostr_events():
    """Display all ingested Nostr events."""
    app = create_app()
    
    with app.app_context():
        # Query for all content items from Nostr sources
        nostr_events = db.session.query(ContentItem)\
            .join(Source)\
            .filter(Source.type == 'nostr')\
            .order_by(ContentItem.publication_date.desc())\
            .all()
        
        if not nostr_events:
            print("No Nostr events found in the database.")
            return
        
        print(f"Found {len(nostr_events)} Nostr events:")
        print("=" * 80)
        
        for i, event in enumerate(nostr_events, 1):
            print(f"\n[{i}] Event ID: {event.id}")
            print(f"    Source: {event.source.identifier} ({event.source.description or 'No description'})")
            print(f"    Nostr Event ID: {event.original_id_on_source}")
            print(f"    Publication Date: {event.publication_date}")
            print(f"    Created At: {event.created_at}")
            print(f"    Initial Distance: {event.initial_distance}")
            print(f"    Language: {event.language_detected or 'Not detected'}")
            
            if event.link_url:
                print(f"    Link URL: {event.link_url}")
            
            # Show content preview (first 200 chars)
            if event.raw_content:
                content_preview = event.raw_content[:200]
                if len(event.raw_content) > 200:
                    content_preview += "..."
                print(f"    Content Preview: {content_preview}")
            
            # Show web content if available
            if event.processed_web_content:
                print(f"    Web Content: {event.processed_web_content.title or 'No title'}")
                print(f"    Web URL: {event.processed_web_content.original_url}")
            
            print("-" * 40)


def display_nostr_events_summary():
    """Display a summary of Nostr events by source."""
    app = create_app()
    
    with app.app_context():
        # Query for summary statistics
        from sqlalchemy import func
        
        summary = db.session.query(
            Source.identifier,
            Source.description,
            func.count(ContentItem.id).label('event_count'),
            func.min(ContentItem.publication_date).label('earliest_event'),
            func.max(ContentItem.publication_date).label('latest_event')
        )\
        .join(ContentItem)\
        .filter(Source.type == 'nostr')\
        .group_by(Source.id, Source.identifier, Source.description)\
        .all()
        
        if not summary:
            print("No Nostr sources with events found.")
            return
        
        print("Nostr Events Summary by Source:")
        print("=" * 80)
        
        total_events = 0
        for source_data in summary:
            identifier, description, count, earliest, latest = source_data
            total_events += count
            
            print(f"\nSource: {identifier}")
            print(f"Description: {description or 'No description'}")
            print(f"Total Events: {count}")
            print(f"Date Range: {earliest} to {latest}")
            print("-" * 40)
        
        print(f"\nTotal Nostr Events Across All Sources: {total_events}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Display ingested Nostr events")
    parser.add_argument(
        "--summary", 
        action="store_true", 
        help="Show summary by source instead of detailed list"
    )
    parser.add_argument(
        "--limit", 
        type=int, 
        help="Limit number of events to display (for detailed view)"
    )
    
    args = parser.parse_args()
    
    if args.summary:
        display_nostr_events_summary()
    else:
        if args.limit:
            # Modify the function to accept a limit
            app = create_app()
            with app.app_context():
                nostr_events = db.session.query(ContentItem)\
                    .join(Source)\
                    .filter(Source.type == 'nostr')\
                    .order_by(ContentItem.publication_date.desc())\
                    .limit(args.limit)\
                    .all()
                
                if not nostr_events:
                    print("No Nostr events found in the database.")
                else:
                    print(f"Showing latest {len(nostr_events)} Nostr events:")
                    print("=" * 80)
                    
                    for i, event in enumerate(nostr_events, 1):
                        print(f"\n[{i}] Event ID: {event.id}")
                        print(f"    Source: {event.source.identifier}")
                        print(f"    Nostr Event ID: {event.original_id_on_source}")
                        print(f"    Publication Date: {event.publication_date}")
                        print(f"    Link URL: {event.link_url or 'No link'}")
                        
                        if event.raw_content:
                            content_preview = event.raw_content[:150]
                            if len(event.raw_content) > 150:
                                content_preview += "..."
                            print(f"    Content: {content_preview}")
                        print("-" * 40)
        else:
            display_nostr_events()
