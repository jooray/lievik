"""
Content Ingestion Service for Lievik.

This service handles fetching content from Nostr sources, parsing linked web content,
and running CrewAI preprocessing tasks. It can be executed both on schedule via APScheduler
and on-demand from the web interface.
"""

import asyncio
import logging
import threading
from datetime import datetime, timedelta
from typing import List, Optional

import trafilatura
from flask import current_app, copy_current_request_context

from lievik.app import db
from lievik.models import Source, ContentItem, ProcessedWebContent
from lievik.core.llm_service import get_llm
from lievik.core.crew_service import CrewService
from lievik.sources import SourceRegistry

logger = logging.getLogger(__name__)


class ContentIngestionService:
    """Service for ingesting content from various sources."""

    def __init__(self):
        self.crew_service = CrewService()

    def ingest_all_sources(self, user_id: Optional[int] = None, process_async: bool = True) -> dict:
        """
        Main entry point for content ingestion.

        Args:
            user_id: If provided, only ingest sources for this user. Otherwise, ingest for all users.
            process_async: If True, run CrewAI processing in background thread

        Returns:
            dict: Summary of ingestion results
        """
        try:
            logger.info(f"Starting content ingestion for user_id: {user_id}")

            # Get active sources
            query = Source.query.filter_by(is_active=True)
            if user_id:
                query = query.filter_by(user_id=user_id)

            sources = query.all()
            current_app.logger.info(f"Found {len(sources)} active sources to process.")

            results = {
                'sources_processed': 0,
                'new_content_items': 0,
                'processed_web_pages': 0,
                'crew_processed_items': 0,
                'errors': [],
                'crew_processing_status': 'not_started'
            }

            # Step 1-2: Ingest content from all sources with transaction per source
            for source in sources:
                current_app.logger.info(f"Processing source ID: {source.id}, Identifier: {source.identifier}, Type: {source.type}")
                try:
                    source_result = self._ingest_source_with_transaction(source)
                    results['sources_processed'] += 1
                    results['new_content_items'] += source_result.get('new_items', 0)
                    results['processed_web_pages'] += source_result.get('processed_pages', 0)
                except Exception as e:
                    current_app.logger.error(f"Failed to ingest source {source.id}: {e}")
                    results['errors'].append(f"Source {source.id}: {str(e)}")
                    continue

            current_app.logger.info(f"Content ingestion completed: {results}")

            # Step 3: Execute Global Content Preprocessing Crew for new items
            if results['new_content_items'] > 0:
                if process_async:
                    # Run CrewAI processing in background thread
                    current_app.logger.info(f"Starting background CrewAI processing for {results['new_content_items']} new content items")

                    # Create a copy of the app context for the thread
                    app = current_app._get_current_object()

                    def run_crew_processing():
                        with app.app_context():
                            try:
                                crew_results = self._process_new_content_with_crew()
                                app.logger.info(f"Background CrewAI processing completed for {crew_results.get('items_processed_globally', 0)} items")
                            except Exception as e:
                                app.logger.error(f"Background CrewAI processing failed: {str(e)}", exc_info=True)

                    # Start background thread
                    thread = threading.Thread(target=run_crew_processing, daemon=True)
                    thread.start()
                    results['crew_processing_status'] = 'started_in_background'
                    results['crew_processed_items'] = 'processing_in_background'
                else:
                    # Run synchronously (for testing or manual runs)
                    current_app.logger.info(f"Starting synchronous CrewAI processing for {results['new_content_items']} new content items")
                    try:
                        crew_results = self._process_new_content_with_crew()
                        results['crew_processed_items'] = crew_results.get('items_processed_globally', 0)
                        results['crew_processing_status'] = 'completed'
                        current_app.logger.info(f"CrewAI processing completed for {results['crew_processed_items']} items")
                    except Exception as e:
                        current_app.logger.error(f"CrewAI processing failed: {str(e)}", exc_info=True)
                        results['errors'].append(f"CrewAI processing error: {str(e)}")
                        results['crew_processing_status'] = 'failed'
            else:
                current_app.logger.info("No new content items to process with CrewAI")
                results['crew_processing_status'] = 'no_items_to_process'

            return results

        except Exception as e:
            current_app.logger.error(f"Content ingestion failed: {str(e)}", exc_info=True)
            raise

    def _ingest_source_with_transaction(self, source: Source) -> dict:
        """
        Ingest content from a single source with proper transaction handling.

        Args:
            source: Source model instance

        Returns:
            dict: Results for this source
        """
        # Get the appropriate adapter for this source type
        adapter = SourceRegistry.create_adapter(source.type)
        if not adapter:
            current_app.logger.warning(f"Unsupported source type: {source.type} for source ID: {source.id}")
            return {'new_items': 0, 'processed_pages': 0}

        # Use asyncio to run the async fetch method
        return asyncio.run(self._ingest_with_adapter_transactional(source, adapter))

    async def _ingest_with_adapter_transactional(self, source: Source, adapter) -> dict:
        """
        Ingest content using the appropriate source adapter with transaction per item.

        Args:
            source: Source model instance
            adapter: Source adapter instance

        Returns:
            dict: Results for this source
        """
        try:
            # Fetch content using the adapter
            content_items = await adapter.fetch_content(source)
            results = {'new_items': 0, 'processed_pages': 0}

            for item_data in content_items:
                # Process each item in its own transaction
                try:
                    # Check if content already exists
                    existing_item = ContentItem.query.filter_by(
                        source_id=source.id,
                        content_identifier=item_data['content_identifier']
                    ).first()

                    if existing_item:
                        current_app.logger.debug(f"Content {item_data['content_identifier']} already exists. Skipping.")
                        continue

                    # Create new ContentItem with pending status
                    new_item = ContentItem(
                        source_id=source.id,
                        content_identifier=item_data['content_identifier'],
                        raw_content=item_data['raw_content'],
                        publication_date=item_data['publication_date'],
                        initial_distance=source.base_distance,
                        metadata=item_data.get('content_metadata', {}),
                        processing_status='pending'
                    )

                    # Extract links from content
                    links = adapter.extract_links(item_data['raw_content'])

                    # Store the first link as the primary link_url
                    if links:
                        new_item.link_url = links[0]
                        current_app.logger.info(f"Set primary link URL for content item: {links[0]}")

                    db.session.add(new_item)

                    # Process all extracted links
                    for link_url in links:
                        try:
                            processed_content = self._process_web_content(link_url)
                            if processed_content:
                                new_item.processed_web_content.append(processed_content)
                                results['processed_pages'] += 1
                                current_app.logger.info(f"Processed web content from URL: {link_url}")
                        except Exception as e:
                            current_app.logger.error(f"Failed to process URL {link_url}: {e}")
                            continue

                    # Commit this item
                    db.session.commit()
                    results['new_items'] += 1
                    current_app.logger.info(f"Added new content item {item_data['content_identifier']} for source {source.id}")

                except Exception as e:
                    db.session.rollback()
                    current_app.logger.error(f"Failed to process content item {item_data['content_identifier']}: {e}")
                    continue

            current_app.logger.info(f"Source {source.id} ingestion completed: "
                                   f"{results['new_items']} new items, "
                                   f"{results['processed_pages']} processed pages")

            return results

        except Exception as e:
            current_app.logger.error(f"Error ingesting source {source.id}: {e}", exc_info=True)
            raise

    def _process_web_content(self, url: str) -> Optional[ProcessedWebContent]:
        """
        Process web content from URL using trafilatura.

        Args:
            url: URL to process

        Returns:
            ProcessedWebContent instance or None if processing failed
        """
        try:
            # Check if we already processed this URL
            existing = ProcessedWebContent.query.filter_by(original_url=url).first()
            if existing:
                current_app.logger.info(f"URL {url} already processed. Skipping.")
                return existing

            # Download and extract content
            downloaded = trafilatura.fetch_url(url)
            if not downloaded:
                current_app.logger.warning(f"Failed to download URL: {url}")
                return None

            # Extract main content with metadata
            extracted = trafilatura.extract(downloaded,
                                          include_comments=False,
                                          include_tables=True,
                                          output_format='json',
                                          with_metadata=True)

            if not extracted:
                current_app.logger.warning(f"Failed to extract content from URL: {url}")
                return None

            # Parse the JSON result
            import json
            extracted_data = json.loads(extracted) if isinstance(extracted, str) else extracted

            # Create ProcessedWebContent
            processed_item = ProcessedWebContent(
                original_url=url,
                full_text=extracted_data.get('text', ''),
                title=extracted_data.get('title', ''),
                summary_text=extracted_data.get('description', '')[:500] if extracted_data.get('description') else None,
                # Store the full extracted data as content_metadata (renamed field)
                content_metadata={'trafilatura_metadata': extracted_data, 'language': extracted_data.get('language')}
            )
            db.session.add(processed_item)
            current_app.logger.info(f"Successfully processed and stored content from URL: {url}")
            return processed_item

        except Exception as e:
            current_app.logger.error(f"Error processing web content for URL {url}: {e}", exc_info=True)
            return None

    def ingest_from_source(self, source: Source) -> dict:
        """
        Public method to ingest from a specific source.
        Used by manual trigger endpoints.

        Args:
            source: Source instance to ingest from

        Returns:
            dict: Ingestion results for this source
        """
        try:
            current_app.logger.info(f"Manually ingesting source ID: {source.id}, Identifier: {source.identifier}")
            result = self._ingest_source(source)
            db.session.commit()
            current_app.logger.info(f"Manual ingestion for source {source.id} completed: {result}")
            return result
        except Exception as e:
            current_app.logger.error(f"Manual ingestion for source {source.id} failed: {e}")
            db.session.rollback()
            raise

    def _process_new_content_with_crew(self) -> dict:
        """
        Process recently created content items through the Global Content Preprocessing Crew.
        This implements Step 3 of the 4-step pipeline.

        Returns:
            dict: Processing results
        """
        try:
            from datetime import datetime, timedelta

            # Get content items that are pending or need retry
            pending_items = ContentItem.query.filter(
                ContentItem.processing_status.in_(['pending', 'retry'])
            ).order_by(ContentItem.created_at.desc()).limit(100).all()

            current_app.logger.info(f"Found {len(pending_items)} pending content items to process with CrewAI")

            processed_count = 0
            failed_count = 0

            for item in pending_items:
                try:
                    # Update status to processing
                    item.processing_status = 'processing'
                    item.processing_attempts += 1
                    item.last_processing_attempt = datetime.utcnow()
                    db.session.commit()

                    current_app.logger.info(f"Processing content item {item.id} with Global Content Preprocessing Crew (attempt {item.processing_attempts})")

                    # Use CrewService to process the content item
                    crew_result = self.crew_service.process_content_item(item, target_channels=None)

                    if crew_result.get('status') == 'completed':
                        item.processing_status = 'completed'
                        item.processing_error = None
                        processed_count += 1
                        current_app.logger.info(f"Successfully processed content item {item.id}")
                    else:
                        # Mark as retry if not completely failed
                        item.processing_status = 'retry' if item.processing_attempts < 3 else 'failed'
                        item.processing_error = crew_result.get('error', 'Unknown error')
                        failed_count += 1
                        current_app.logger.warning(f"Content item {item.id} processing completed with warnings or errors")

                    db.session.commit()

                except Exception as e:
                    db.session.rollback()
                    current_app.logger.error(f"Failed to process content item {item.id}: {str(e)}")

                    # Update item status
                    try:
                        item.processing_status = 'retry' if item.processing_attempts < 3 else 'failed'
                        item.processing_error = str(e)
                        db.session.commit()
                        failed_count += 1
                    except:
                        db.session.rollback()

                    continue

            return {
                'items_processed_globally': processed_count,
                'items_failed': failed_count,
                'total_pending_items': len(pending_items)
            }

        except Exception as e:
            current_app.logger.error(f"Error in CrewAI processing: {str(e)}", exc_info=True)
            db.session.rollback()
            raise

    def retry_failed_items(self, max_items: int = 50) -> dict:
        """
        Retry processing for failed items.

        Args:
            max_items: Maximum number of items to retry

        Returns:
            dict: Retry results
        """
        try:
            # Get failed items that haven't exceeded max attempts
            failed_items = ContentItem.query.filter(
                ContentItem.processing_status == 'retry',
                ContentItem.processing_attempts < 3
            ).order_by(ContentItem.last_processing_attempt.asc()).limit(max_items).all()

            current_app.logger.info(f"Found {len(failed_items)} failed items to retry")

            for item in failed_items:
                item.processing_status = 'pending'

            db.session.commit()

            # Process them
            return self._process_new_content_with_crew()

        except Exception as e:
            current_app.logger.error(f"Error retrying failed items: {e}")
            db.session.rollback()
            raise


# Service instance
content_ingestion_service = ContentIngestionService()


def run_content_ingestion(user_id: Optional[int] = None) -> dict:
    """
    Enhanced wrapper function for running the complete content ingestion pipeline
    within Flask app context. This is the function that will be called by APScheduler.

    This implements the complete pipeline as specified in Task 2.4:
    1. Fetch new events from sources
    2. For each event, parse links (if any)
    3. Execute the Global Content Preprocessing Crew (summarization, distance evaluation, language detection)
    4. Store ContentItems and ProcessedWebContent

    Args:
        user_id: Optional user ID to limit ingestion to specific user

    Returns:
        dict: Results of ingestion pipeline
    """
    try:
        current_app.logger.info("=== Starting Content Ingestion Pipeline ===")

        # Step 1-4: Execute the main ingestion pipeline
        # Pass user_id=None to ingest for all users when run by scheduler
        # Use process_async=True to run CrewAI in background
        results = content_ingestion_service.ingest_all_sources(user_id=None, process_async=True)

        # Enhanced result reporting
        total_new_items = results.get('new_content_items', 0)
        total_processed_pages = results.get('processed_web_pages', 0)
        total_sources = results.get('sources_processed', 0)
        crew_status = results.get('crew_processing_status', 'unknown')
        errors = results.get('errors', [])

        current_app.logger.info(f"=== Content Ingestion Pipeline Completed ===")
        current_app.logger.info(f"Sources processed: {total_sources}")
        current_app.logger.info(f"New content items: {total_new_items}")
        current_app.logger.info(f"Web pages processed: {total_processed_pages}")
        current_app.logger.info(f"CrewAI processing status: {crew_status}")

        if errors:
            current_app.logger.error(f"Pipeline encountered errors: {errors}")

        # Add pipeline metrics
        results['pipeline_status'] = 'completed'
        results['total_steps_completed'] = 4

        return results

    except Exception as e:
        current_app.logger.error(f"=== Content Ingestion Pipeline Failed ===", exc_info=True)
        return {
            'pipeline_status': 'failed',
            'error': str(e),
            'sources_processed': 0,
            'new_content_items': 0,
            'processed_web_pages': 0,
            'total_steps_completed': 0
        }
