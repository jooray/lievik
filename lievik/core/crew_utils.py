"""
Utility functions for CrewAI operations.
Provides common functionality for parsing and processing CrewAI outputs.
"""

import json
import re
import logging
from typing import Dict, Any, Optional, Tuple

logger = logging.getLogger(__name__)


def clean_llm_json_output(text: str) -> str:
    """
    Cleans potential Markdown code block fences and other formatting from LLM JSON output.

    Args:
        text: Raw text output from LLM that may contain JSON with markdown formatting

    Returns:
        Cleaned text with markdown fences removed
    """
    if text is None:
        return ""

    # Remove Markdown code block fences (e.g., ```json ... ``` or ``` ... ```)
    match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text, re.DOTALL)
    if match:
        text = match.group(1)

    # Strip leading/trailing whitespace
    text = text.strip()
    return text


def parse_crew_json_output(result: Any, context: str = "") -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Parses JSON output from CrewAI result objects.
    Attempts to use result.json_dict first, then falls back to parsing raw output.

    Args:
        result: CrewAI result object (typically CrewOutput)
        context: Optional context string for logging (e.g., "content_item_123")

    Returns:
        Tuple of (parsed_dict, json_string):
            - parsed_dict: Parsed JSON as dict, or None if parsing failed
            - json_string: The JSON string to store (either formatted from dict or cleaned raw text)
    """
    parsed_result = None
    stored_json_string = None

    # Try to use CrewAI's built-in JSON parsing first
    if hasattr(result, 'json_dict') and isinstance(result.json_dict, dict) and result.json_dict:
        logger.info(f"Using result.json_dict from CrewAI{f' for {context}' if context else ''}")
        parsed_result = result.json_dict
        try:
            stored_json_string = json.dumps(parsed_result, indent=2)
        except (TypeError, OverflowError) as e:
            logger.warning(f"Could not serialize result.json_dict{f' for {context}' if context else ''}: {e}")
            parsed_result = None  # Force fallback

    if parsed_result is None:  # Fallback to raw output processing
        logger.info(f"result.json_dict not available{f' for {context}' if context else ''}, processing raw output")
        raw_output_text = ""
        if hasattr(result, 'raw') and result.raw is not None:
            raw_output_text = result.raw
        elif result is not None:
            raw_output_text = str(result)

        cleaned_json_text = clean_llm_json_output(raw_output_text)

        try:
            parsed_result = json.loads(cleaned_json_text)
            stored_json_string = json.dumps(parsed_result, indent=2)  # Store consistently formatted JSON
        except json.JSONDecodeError:
            logger.warning(
                f"Crew result{f' for {context}' if context else ''} is not valid JSON after cleaning. "
                f"Cleaned: {cleaned_json_text[:200]}..."
            )
            stored_json_string = cleaned_json_text  # Store the problematic cleaned text
            # parsed_result remains None

    return parsed_result, stored_json_string


def extract_json_content_field(raw_content: str) -> str:
    """
    Extracts actual content from JSON-formatted raw content.
    Specifically handles Nostr events and similar JSON structures.

    Args:
        raw_content: Raw content that might be JSON

    Returns:
        Extracted content text or original content if not JSON
    """
    content_text = raw_content or ''

    # If content looks like JSON (starts with '{'), try to parse it
    if content_text.strip().startswith('{'):
        try:
            parsed_json = json.loads(content_text)
            # If it's a Nostr event or similar, extract the content field
            if 'content' in parsed_json:
                content_text = parsed_json['content']
                # Replace literal \n with actual newlines
                content_text = content_text.replace('\\n', '\n')
        except json.JSONDecodeError:
            # If parsing fails, use the original text
            pass

    return content_text


def create_error_json(error: Exception) -> str:
    """
    Creates a properly formatted JSON string for error cases.

    Args:
        error: The exception that occurred

    Returns:
        JSON string containing error information
    """
    return json.dumps({'error': str(error)}, indent=2)
