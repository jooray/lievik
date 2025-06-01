"""
Nostr source adapter for content ingestion.
"""

import re
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from urllib.parse import urlparse

from nostr_sdk import Client, Filter, Event, Events, Keys, PublicKey, Timestamp, Kind, KindStandard, EventId
from flask import current_app

from lievik.models import Source, ContentItem
from . import BaseSourceAdapter, SourceRegistry


class NostrSourceAdapter(BaseSourceAdapter):
    """Adapter for fetching content from Nostr sources."""

    def __init__(self):
        self.client = None

    async def _get_client(self) -> Client:
        """Get or create Nostr client."""
        if self.client is None:
            self.client = Client()
            # Add relays and connect
            try:
                await self.client.add_relay("wss://relay.damus.io")
                await self.client.add_relay("wss://nos.lol")
                await self.client.add_relay("wss://relay.nostr.band")
                await self.client.connect()
                current_app.logger.info("Nostr client connected to relays.")
            except Exception as e:
                current_app.logger.error(f"Error connecting Nostr client: {e}")
                raise
        return self.client

    async def fetch_content(self, source: Source, since: Optional[datetime] = None) -> List[Dict]:
        """
        Fetch content from a Nostr source.

        Args:
            source: Source model instance with type='nostr'
            since: Optional datetime to fetch content from

        Returns:
            List of content dictionaries
        """
        try:
            client = await self._get_client()
            current_app.logger.info(f"Got nostr client for source {source.id}")

            # Parse the npub identifier
            try:
                public_key = PublicKey.parse(source.identifier)
                current_app.logger.info(f"Parsed public key for source {source.id}: {public_key.to_hex()}")
            except Exception as e:
                current_app.logger.error(f"Error parsing npub {source.identifier} for source {source.id}: {e}")
                raise

            # Determine time filter
            if not since:
                # Check for latest content from this source
                latest_content = ContentItem.query.filter_by(source_id=source.id)\
                    .order_by(ContentItem.publication_date.desc())\
                    .first()

                if latest_content:
                    since = latest_content.publication_date - timedelta(days=3)
                    current_app.logger.info(f"Found latest content for source {source.id} at {latest_content.publication_date}. Fetching since {since}")
                else:
                    since = datetime.utcnow() - timedelta(days=365*5)  # Default to 5 years
                    current_app.logger.info(f"No existing content for source {source.id}. Fetching since {since}.")

            since_timestamp = Timestamp.from_secs(int(since.timestamp()))

            # Create filter
            text_note_kind = Kind.from_std(KindStandard.TEXT_NOTE)
            long_form_kind = Kind(30023)  # NIP-23 long-form content
            repost_kind = Kind(6)  # NIP-18 reposts

            event_filter = Filter()\
                .author(public_key)\
                .since(since_timestamp)\
                .kinds([text_note_kind, long_form_kind, repost_kind])\
                .limit(5000)

            current_app.logger.info(f"Created filter: {event_filter.as_json()}")

            # Fetch events
            try:
                current_app.logger.info(f"Fetching events for source {source.id} with filter: {event_filter.as_json()}")
                from datetime import timedelta as td
                events: Events = await client.fetch_events(event_filter, td(seconds=30))
                current_app.logger.info(f"Fetched events for source {source.id}")
            except Exception as e:
                current_app.logger.error(f"Error fetching events for source {source.id}: {e}")
                raise

            # Convert events to list
            events_list = events.to_vec()
            current_app.logger.info(f"Successfully converted to list with {len(events_list)} events")

            # Collect reposted event IDs and filter out replies
            reposted_event_ids = []
            repost_map = {}  # Map reposted event ID to repost event
            filtered_events = []

            for event in events_list:
                # Check if this is a reply (has e-tag with "reply" marker)
                is_reply = False
                tags = event.tags().to_vec()

                for tag in tags:
                    # Check for e-tag with "reply" marker in position 3 (0-indexed)
                    if (isinstance(tag, list) and len(tag) >= 4 and
                        tag[0] == 'e' and tag[3] == 'reply'):
                        is_reply = True
                        current_app.logger.debug(f"Skipping reply event {event.id().to_hex()} with reply marker")
                        break

                if is_reply:
                    continue  # Skip this event

                # Add to filtered events if not a reply
                filtered_events.append(event)

                # Check for reposts
                if event.kind().as_u16() == 6:  # Repost event
                    for tag in tags:
                        # tag is already a list after to_vec()
                        if isinstance(tag, list) and len(tag) >= 2 and tag[0] == 'e':
                            reposted_event_id = tag[1]
                            reposted_event_ids.append(reposted_event_id)
                            repost_map[reposted_event_id] = event
                            current_app.logger.debug(f"Found repost of event {reposted_event_id}")
                            break  # Usually only one 'e' tag per repost

            # Update events_list to use filtered events
            events_list = filtered_events
            current_app.logger.info(f"Filtered to {len(events_list)} events after removing replies")

            # Fetch reposted events if any
            original_events_map = {}
            if reposted_event_ids:
                try:
                    current_app.logger.info(f"Fetching {len(reposted_event_ids)} reposted events")
                    # Convert string IDs to EventId objects
                    event_ids = [EventId.parse(eid) for eid in reposted_event_ids]
                    original_filter = Filter().ids(event_ids)
                    original_events: Events = await client.fetch_events(original_filter, td(seconds=30))

                    # Create map of original events
                    for original_event in original_events.to_vec():
                        original_events_map[original_event.id().to_hex()] = original_event

                    current_app.logger.info(f"Fetched {len(original_events_map)} original events")
                except Exception as e:
                    current_app.logger.error(f"Error fetching reposted events: {e}")
                    # Continue processing even if we can't fetch originals

            # Convert events to generic content format
            content_items = []

            for event in events_list:
                event_id_hex = event.id().to_hex()
                current_app.logger.debug(f"Processing event ID: {event_id_hex} for source {source.id}")

                # Handle reposts specially
                if event.kind().as_u16() == 6:
                    # Start with repost content (might include a comment)
                    content_parts = []
                    repost_content = event.content()

                    # Check if repost has additional content (quoted repost with comment)
                    if repost_content.strip():
                        content_parts.append(repost_content)

                    # Find the original event
                    original_event = None
                    tags_vec = event.tags().to_vec()  # Convert Tags to list
                    for tag in tags_vec:
                        # tag is already a list after to_vec()
                        if isinstance(tag, list) and len(tag) >= 2 and tag[0] == 'e':
                            reposted_id = tag[1]
                            original_event = original_events_map.get(reposted_id)
                            break

                    # Add original event content
                    if original_event:
                        original_content = original_event.content()
                        content_parts.append(f"\n\n--- Reposted ---\n{original_content}")

                        # Combine content
                        combined_content = "\n".join(content_parts)

                        content_items.append({
                            'content_identifier': event_id_hex,
                            'raw_content': combined_content,
                            'publication_date': datetime.fromtimestamp(event.created_at().as_secs()),
                            'content_metadata': {  # Changed from 'metadata'
                                'event_id': event_id_hex,
                                'author': public_key.to_hex(),
                                'kind': event.kind().as_u16(),
                                'reposted_event_id': original_event.id().to_hex(),
                                'reposted_author': original_event.author().to_hex(),
                                'reposted_kind': original_event.kind().as_u16(),
                                'full_event': event.as_json()  # Store full event JSON in metadata
                            }
                        })
                    else:
                        # If we couldn't fetch the original, still include the repost
                        content_items.append({
                            'content_identifier': event_id_hex,
                            'raw_content': repost_content or "[Repost - original content unavailable]",
                            'publication_date': datetime.fromtimestamp(event.created_at().as_secs()),
                            'content_metadata': {  # Changed from 'metadata'
                                'event_id': event_id_hex,
                                'author': public_key.to_hex(),
                                'kind': event.kind().as_u16(),
                                'repost': True,
                                'full_event': event.as_json()  # Store full event JSON in metadata
                            }
                        })
                else:
                    # Regular event (not a repost)
                    content_items.append({
                        'content_identifier': event_id_hex,
                        'raw_content': event.content(),
                        'publication_date': datetime.fromtimestamp(event.created_at().as_secs()),
                        'content_metadata': {  # Changed from 'metadata'
                            'event_id': event_id_hex,
                            'author': public_key.to_hex(),
                            'kind': event.kind().as_u16(),
                            'full_event': event.as_json()  # Store full event JSON in metadata
                        }
                    })

            current_app.logger.info(f"Processed {len(content_items)} events for source {source.id}")
            return content_items

        except Exception as e:
            current_app.logger.error(f"Error fetching Nostr content for source {source.id}: {e}", exc_info=True)
            raise

    def extract_links(self, content: str) -> List[str]:
        """Extract HTTP/HTTPS URLs from text."""
        # Split content by whitespace and newlines to isolate potential URLs
        tokens = re.split(r'[\s\n]+', content)

        urls = []

        # Also use regex to find URLs that might be embedded in text
        url_pattern = r'https?://[^\s<>"\'{}|\\^`\[\]\n]+(?:[^\s<>"\',.\n]|(?<=[a-zA-Z0-9])[/.])*'
        found_urls = re.findall(url_pattern, content)

        # Split found URLs on \n sequences to handle concatenated URLs
        for url in found_urls:
            # Split on both literal \n and actual newlines
            parts = re.split(r'\\n|\n', url)
            for part in parts:
                part = part.strip()
                if part and not part.startswith('nostr:'):
                    urls.append(part)

        # Check tokens for URLs
        for token in tokens:
            # Skip if token contains nostr: prefix
            if 'nostr:' in token:
                # TODO: Handle nostr: event references (e.g., nostr:nevent1...)
                # These could be fetched using the Nostr client to expand referenced events
                continue

            # Split token on \n sequences before processing
            token_parts = re.split(r'\\n|\n', token)
            for part in token_parts:
                part = part.strip()
                if not part or part.startswith('nostr:'):
                    continue

                # Check if part looks like a URL
                if part.startswith(('http://', 'https://')):
                    urls.append(part)
                elif re.match(r'^(?:www\.)?[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?$', part):
                    # URL without protocol
                    urls.append('https://' + part)

        # Deduplicate and validate URLs
        valid_urls = []
        seen = set()

        for url in urls:
            # Skip empty URLs
            if not url:
                continue

            # Clean up URL - remove trailing punctuation and special characters
            url = re.sub(r'[.,;:!?\'")\]}\s\\]+$', '', url)

            # Skip if URL is too short or doesn't contain a domain
            if len(url) < 10 or '.' not in url:
                continue

            try:
                parsed = urlparse(url)
                # Validate that we have a proper domain
                if parsed.netloc and '.' in parsed.netloc and parsed.scheme in ['http', 'https'] and url not in seen:
                    valid_urls.append(url)
                    seen.add(url)
                    current_app.logger.debug(f"Extracted valid URL: {url}")
            except Exception as e:
                current_app.logger.debug(f"Invalid URL skipped: {url}, error: {e}")
                continue

        return valid_urls


# Register the adapter
SourceRegistry.register('nostr', NostrSourceAdapter)
