"""
Source adapters for content ingestion.
"""

from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Type
from datetime import datetime

from lievik.models import Source, ContentItem


class BaseSourceAdapter(ABC):
    """Abstract base class for all source adapters."""

    @abstractmethod
    async def fetch_content(self, source: Source, since: Optional[datetime] = None) -> List[Dict]:
        """
        Fetch content from the source.

        Args:
            source: Source model instance
            since: Optional datetime to fetch content from

        Returns:
            List of dictionaries containing:
                - content_identifier: Unique identifier for the content
                - raw_content: The actual content text
                - publication_date: When the content was published
                - metadata: Optional dict with source-specific metadata
        """
        pass

    @abstractmethod
    def extract_links(self, content: str) -> List[str]:
        """Extract URLs from content text."""
        pass


class SourceRegistry:
    """Registry for source adapters."""

    _adapters: Dict[str, Type[BaseSourceAdapter]] = {}

    @classmethod
    def register(cls, source_type: str, adapter_class: Type[BaseSourceAdapter]):
        """Register a source adapter."""
        cls._adapters[source_type] = adapter_class

    @classmethod
    def get_adapter(cls, source_type: str) -> Optional[Type[BaseSourceAdapter]]:
        """Get adapter class for source type."""
        return cls._adapters.get(source_type)

    @classmethod
    def create_adapter(cls, source_type: str) -> Optional[BaseSourceAdapter]:
        """Create an instance of the adapter for the given source type."""
        adapter_class = cls.get_adapter(source_type)
        if adapter_class:
            return adapter_class()
        return None


# Import adapters to register them
from .nostr import NostrSourceAdapter

__all__ = ['BaseSourceAdapter', 'SourceRegistry', 'NostrSourceAdapter']
