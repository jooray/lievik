#!/usr/bin/env python3
"""
Cleanup script to remove imported crew configuration and Nostr content.
This allows reprocessing with updated crew configurations.

Usage:
    poetry run python scripts/cleanup_crew_and_content.py [--all | --crew | --content]

Options:
    --all     Remove both crew config and content (default)
    --crew    Remove only crew configuration
    --content Remove only Nostr content
    --dry-run Show what would be deleted without actually deleting
"""

import sys
import os
import argparse
from datetime import datetime

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lievik.app import create_app, db
from lievik.models import (
    CrewConfiguration, ContentItem, Source, ProcessedWebContent,
    ChannelContentAffinity
)
from sqlalchemy import func


def cleanup_crew_configuration(dry_run=False):
    """Remove the Global Content Preprocessing Crew configuration."""
    print("\n=== Cleaning up Crew Configuration ===")

    # Find the global crew configuration
    global_crew = CrewConfiguration.query.filter_by(
        name="Global Content Preprocessing Crew",
        is_global=True
    ).first()

    if not global_crew:
        print("✓ No Global Content Preprocessing Crew configuration found.")
        return 0

    print(f"Found crew configuration: {global_crew.name} (ID: {global_crew.id})")

    if dry_run:
        print("DRY RUN: Would delete this crew configuration.")
        return 1

    # Delete the configuration
    db.session.delete(global_crew)
    db.session.commit()
    print("✓ Deleted Global Content Preprocessing Crew configuration.")

    return 1


def cleanup_nostr_content(dry_run=False):
    """Remove all content from Nostr sources and related data."""
    print("\n=== Cleaning up Nostr Content ===")

    # Get statistics first
    nostr_sources = Source.query.filter_by(type='nostr').all()
    if not nostr_sources:
        print("✓ No Nostr sources found.")
        return 0

    print(f"Found {len(nostr_sources)} Nostr sources:")
    for source in nostr_sources:
        print(f"  - {source.identifier} ({source.description or 'No description'})")

    # Get IDs of content items from Nostr sources
    nostr_content_ids = db.session.query(ContentItem.id)\
        .join(Source)\
        .filter(Source.type == 'nostr')\
        .all()

    nostr_content_ids = [id[0] for id in nostr_content_ids]  # Extract IDs from tuples
    nostr_content_count = len(nostr_content_ids)

    if nostr_content_count == 0:
        print("✓ No content items from Nostr sources found.")
        return 0

    print(f"\nFound {nostr_content_count} content items from Nostr sources.")

    if dry_run:
        # Show what would be deleted
        print("\nDRY RUN: Would delete:")

        # Count related ProcessedWebContent - need to check the actual relationship
        # Since ProcessedWebContent might be linked via ContentItem's processed_web_content relationship
        web_content_count = db.session.query(func.count(ProcessedWebContent.id))\
            .join(ContentItem, ContentItem.processed_web_content_id == ProcessedWebContent.id)\
            .filter(ContentItem.id.in_(nostr_content_ids))\
            .scalar() if nostr_content_ids else 0
        print(f"  - {web_content_count} ProcessedWebContent entries")

        # Count related ChannelContentAffinity
        affinity_count = db.session.query(func.count(ChannelContentAffinity.id))\
            .filter(ChannelContentAffinity.content_item_id.in_(nostr_content_ids))\
            .scalar() if nostr_content_ids else 0
        print(f"  - {affinity_count} ChannelContentAffinity entries")

        print(f"  - {nostr_content_count} ContentItem entries")

        return nostr_content_count

    # Delete in correct order to respect foreign key constraints
    deleted_counts = {}

    # 1. Delete ChannelContentAffinity entries
    if nostr_content_ids:
        affinity_count = ChannelContentAffinity.query\
            .filter(ChannelContentAffinity.content_item_id.in_(nostr_content_ids))\
            .count()
        deleted_counts['affinities'] = affinity_count

        if affinity_count > 0:
            ChannelContentAffinity.query\
                .filter(ChannelContentAffinity.content_item_id.in_(nostr_content_ids))\
                .delete(synchronize_session=False)
    else:
        deleted_counts['affinities'] = 0

    # 2. Delete ProcessedWebContent entries that are linked to these ContentItems
    if nostr_content_ids:
        # Get the ProcessedWebContent IDs that are linked to our ContentItems
        linked_web_content_ids = db.session.query(ProcessedWebContent.id)\
            .join(ContentItem, ContentItem.processed_web_content_id == ProcessedWebContent.id)\
            .filter(ContentItem.id.in_(nostr_content_ids))\
            .all()

        linked_web_content_ids = [id[0] for id in linked_web_content_ids]
        deleted_counts['web_content'] = len(linked_web_content_ids)

        if linked_web_content_ids:
            ProcessedWebContent.query\
                .filter(ProcessedWebContent.id.in_(linked_web_content_ids))\
                .delete(synchronize_session=False)
    else:
        deleted_counts['web_content'] = 0

    # 3. Delete ContentItem entries
    deleted_counts['content_items'] = nostr_content_count
    if nostr_content_ids:
        ContentItem.query\
            .filter(ContentItem.id.in_(nostr_content_ids))\
            .delete(synchronize_session=False)

    # Commit all deletions
    db.session.commit()

    print("\nDeleted:")
    print(f"  ✓ {deleted_counts['affinities']} ChannelContentAffinity entries")
    print(f"  ✓ {deleted_counts['web_content']} ProcessedWebContent entries")
    print(f"  ✓ {deleted_counts['content_items']} ContentItem entries")

    return deleted_counts['content_items']


def show_current_state():
    """Display current state of crew configuration and content."""
    print("\n=== Current Database State ===")

    # Crew configurations
    crew_count = CrewConfiguration.query.count()
    global_crew_count = CrewConfiguration.query.filter_by(is_global=True).count()
    print(f"\nCrew Configurations:")
    print(f"  - Total: {crew_count}")
    print(f"  - Global: {global_crew_count}")

    # Sources
    total_sources = Source.query.count()
    nostr_sources = Source.query.filter_by(type='nostr').count()
    print(f"\nSources:")
    print(f"  - Total: {total_sources}")
    print(f"  - Nostr: {nostr_sources}")

    # Content
    total_content = ContentItem.query.count()
    nostr_content = db.session.query(func.count(ContentItem.id))\
        .join(Source)\
        .filter(Source.type == 'nostr')\
        .scalar()
    print(f"\nContent Items:")
    print(f"  - Total: {total_content}")
    print(f"  - From Nostr: {nostr_content}")

    # Processed web content
    total_web = ProcessedWebContent.query.count()
    print(f"\nProcessed Web Content:")
    print(f"  - Total: {total_web}")

    # Channel affinities
    total_affinities = ChannelContentAffinity.query.count()
    print(f"\nChannel Content Affinities:")
    print(f"  - Total: {total_affinities}")


def main():
    """Main function to handle command line arguments and execute cleanup."""
    parser = argparse.ArgumentParser(
        description="Cleanup crew configuration and/or Nostr content from database"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Remove both crew configuration and content (default)"
    )
    parser.add_argument(
        "--crew",
        action="store_true",
        help="Remove only crew configuration"
    )
    parser.add_argument(
        "--content",
        action="store_true",
        help="Remove only Nostr content"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be deleted without actually deleting"
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Show current database state without deleting anything"
    )

    args = parser.parse_args()

    # Default to --all if no specific option is given
    if not args.crew and not args.content and not args.status:
        args.all = True

    # Create Flask app context
    app = create_app()

    with app.app_context():
        start_time = datetime.utcnow()

        print("Lievik Cleanup Script")
        print("=" * 50)

        # Show current state first
        show_current_state()

        if args.status:
            # Just show status, don't delete anything
            return

        if args.dry_run:
            print("\n⚠️  DRY RUN MODE - Nothing will be deleted")

        total_deleted = 0

        # Cleanup crew configuration
        if args.all or args.crew:
            deleted = cleanup_crew_configuration(dry_run=args.dry_run)
            total_deleted += deleted

        # Cleanup content
        if args.all or args.content:
            deleted = cleanup_nostr_content(dry_run=args.dry_run)
            total_deleted += deleted

        # Show final summary
        elapsed = (datetime.utcnow() - start_time).total_seconds()
        print(f"\n=== Cleanup {'Preview' if args.dry_run else 'Complete'} ===")
        print(f"Time elapsed: {elapsed:.2f} seconds")

        if not args.dry_run:
            print(f"Total items deleted: {total_deleted}")
            print("\n✓ Database is ready for fresh content ingestion and crew processing.")
            print("\nNext steps:")
            print("1. Restart the application to re-seed the crew configuration")
            print("2. Run content ingestion: poetry run python scripts/test_ingestion.py")
        else:
            print(f"\nDRY RUN: Would delete approximately {total_deleted} items.")
            print("Run without --dry-run to actually perform the cleanup.")


if __name__ == "__main__":
    main()
