"""
CrewAI service for content processing and evaluation.
Implements database-driven crew management for global and channel-specific processing.
"""

import os
import json
import logging
from typing import Dict, List, Optional, Any
from datetime import datetime

from crewai import Agent, Task, Crew, Process
import yaml

from lievik.core.llm_service import get_llm
from lievik.models import ContentItem, Channel, ProcessedWebContent, CrewConfiguration
from lievik.app import db


logger = logging.getLogger(__name__)


class GlobalContentPreprocessingCrew:
    """
    Global Content Preprocessing Crew that analyzes and enhances raw content
    before channel-specific evaluation. Built dynamically from database configuration.
    """

    def __init__(self, default_llm_provider: Optional[str] = None, default_llm_model: Optional[str] = None):
        """Initialize the preprocessing crew from database configuration."""
        self.default_llm_provider = default_llm_provider
        self.default_llm_model = default_llm_model
        self.default_llm = get_llm(provider_name=self.default_llm_provider, model_name=self.default_llm_model)

        # Load configuration from database
        crew_config = CrewConfiguration.query.filter_by(name="Global Content Preprocessing Crew", is_global=True).first()
        if not crew_config:
            raise ValueError("Global Content Preprocessing Crew configuration not found in database. Please ensure initial data seeding has been completed.")

        # Parse YAML configuration
        try:
            self.config = yaml.safe_load(crew_config.config_yaml)
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML configuration for Global Content Preprocessing Crew: {e}")

        # Build crew from configuration
        self.crew = self._create_crew_from_config()

    def _get_agent_llm(self, agent_config: Dict[str, Any]) -> Any:
        """
        Gets the LLM for a specific agent based on its configuration.
        Uses agent-specific config if available, otherwise falls back to default LLM.
        """
        llm_config = agent_config.get('llm_config', {})
        if llm_config and llm_config.get('provider_name'):
            return get_llm(
                provider_name=llm_config.get('provider_name'),
                model_name=llm_config.get('model_name')
            )
        return self.default_llm

    def _create_crew_from_config(self) -> Crew:
        """Dynamically build a Crew from database YAML configuration."""
        agents_map = {}

        # Create agents
        for agent_config in self.config.get('agents', []):
            agent_llm = self._get_agent_llm(agent_config)

            agent = Agent(
                role=agent_config['role'],
                goal=agent_config['goal'],
                backstory=agent_config['backstory'],
                verbose=agent_config.get('verbose', True),
                allow_delegation=agent_config.get('allow_delegation', False),
                llm=agent_llm
            )
            agents_map[agent_config['role']] = agent

        # Create tasks
        tasks = []
        for task_config in self.config.get('tasks', []):
            # Get the agent for this task
            agent_role = task_config['agent']
            if agent_role not in agents_map:
                raise ValueError(f"Agent '{agent_role}' not found for task '{task_config.get('description', 'Unknown')}'")

            task = Task(
                description=task_config['description'],
                expected_output=task_config['expected_output'],
                agent=agents_map[agent_role]
            )
            tasks.append(task)

        # Create and return Crew
        crew = Crew(
            agents=list(agents_map.values()),
            tasks=tasks,
            verbose=True,
            process=Process.sequential
        )
        return crew

    def process_content(self, content_item: ContentItem) -> Dict[str, Any]:
        """
        Process a content item through the global preprocessing crew.

        Args:
            content_item: ContentItem instance to process

        Returns:
            Dict containing analysis results, enhanced content, and quality assessment
        """
        try:
            # Get the actual content text, not raw JSON
            content_text = content_item.raw_content or ''

            # If content looks like JSON (starts with '{'), try to parse it
            if content_text.strip().startswith('{'):
                try:
                    import json
                    parsed_json = json.loads(content_text)
                    # If it's a Nostr event, extract the content field
                    if 'content' in parsed_json:
                        content_text = parsed_json['content']
                        # Replace literal \n with actual newlines
                        content_text = content_text.replace('\\n', '\n')
                except json.JSONDecodeError:
                    # If parsing fails, use the original text
                    pass

            # Prepare inputs for the crew - ensure all template variables are provided
            crew_inputs = {
                'content': content_text,
                'source_info': f"Distance: {content_item.initial_distance}, Source: {content_item.source.identifier if content_item.source else 'Unknown'}",
                'publication_date': content_item.publication_date.isoformat() if content_item.publication_date else 'Unknown',
                'link_url': content_item.link_url if content_item.link_url else 'No link available'
            }

            # Add processed web content if available
            web_content_analysis = {}
            if content_item.processed_web_content:
                # Get the first processed web content item
                first_web_content = content_item.processed_web_content[0] if content_item.processed_web_content else None
                if first_web_content:
                    crew_inputs.update({
                        'web_title': first_web_content.title or '',
                        'web_content': first_web_content.full_text or '',
                        'web_summary': first_web_content.summary_text or ''
                    })
                    # Store reference for later update
                    web_content_analysis['web_content_id'] = first_web_content.id
                else:
                    # Provide empty values for web content when not available
                    crew_inputs.update({
                        'web_title': '',
                        'web_content': '',
                        'web_summary': ''
                    })
            else:
                # Provide empty values for web content when not available
                crew_inputs.update({
                    'web_title': '',
                    'web_content': '',
                    'web_summary': ''
                })

            # Execute the crew
            logger.info(f"Processing content item {content_item.id} through Global Content Preprocessing Crew")
            result = self.crew.kickoff(inputs=crew_inputs)

            # Parse the result - expecting JSON format
            try:
                if hasattr(result, 'raw'):
                    result_text = result.raw
                else:
                    result_text = str(result)

                # Try to parse as JSON
                parsed_result = json.loads(result_text)

                # Extract structured data
                return {
                    'crew_result_json': result_text,
                    'enhanced_short': parsed_result.get('enhanced_short', ''),
                    'enhanced_medium': parsed_result.get('enhanced_medium', ''),
                    'enhanced_long': parsed_result.get('enhanced_long', ''),
                    'analysis': parsed_result.get('analysis', {}),
                    'quality_score': parsed_result.get('quality_score', 0),
                    # Include web content specific enhancements if available
                    'web_enhanced_short': parsed_result.get('web_enhanced_short', ''),
                    'web_enhanced_medium': parsed_result.get('web_enhanced_medium', ''),
                    'web_enhanced_long': parsed_result.get('web_enhanced_long', ''),
                    'web_summary': parsed_result.get('web_summary', ''),
                    'web_content_id': web_content_analysis.get('web_content_id')
                }

            except json.JSONDecodeError:
                # If not JSON, store raw result
                logger.warning(f"Crew result for content item {content_item.id} is not valid JSON, storing as raw text")
                return {
                    'crew_result_json': result_text,
                    'enhanced_short': '',
                    'enhanced_medium': '',
                    'enhanced_long': '',
                    'analysis': {'raw_result': result_text},
                    'quality_score': 0,
                    'web_enhanced_short': '',
                    'web_enhanced_medium': '',
                    'web_enhanced_long': '',
                    'web_summary': '',
                    'web_content_id': web_content_analysis.get('web_content_id')
                }

        except Exception as e:
            logger.error(f"Error processing content item {content_item.id} with Global Content Preprocessing Crew: {e}")
            return {
                'crew_result_json': json.dumps({'error': str(e)}),
                'enhanced_short': '',
                'enhanced_medium': '',
                'enhanced_long': '',
                'analysis': {'error': str(e)},
                'quality_score': 0,
                'web_enhanced_short': '',
                'web_enhanced_medium': '',
                'web_enhanced_long': '',
                'web_summary': '',
                'web_content_id': None
            }


class ChannelContentEvaluationCrew:
    """
    Channel-specific content evaluation crew that determines
    if content is suitable for specific channels. Built dynamically from database configuration.
    """

    def __init__(self, channel: Channel, default_llm_provider: Optional[str] = None, default_llm_model: Optional[str] = None):
        """Initialize crew for a specific channel from database configuration."""
        self.channel = channel
        self.default_llm_provider = default_llm_provider
        self.default_llm_model = default_llm_model
        self.default_llm = get_llm(provider_name=self.default_llm_provider, model_name=self.default_llm_model)

        # Load configuration from database - first check channel-specific, then channel type default
        crew_config = None
        if channel.crew_configuration_id:
            crew_config = CrewConfiguration.query.get(channel.crew_configuration_id)

        if not crew_config and channel.channel_type and channel.channel_type.default_crew_configuration_id:
            crew_config = CrewConfiguration.query.get(channel.channel_type.default_crew_configuration_id)

        if not crew_config:
            # Create a basic evaluation crew configuration on the fly
            logger.warning(f"No crew configuration found for channel {channel.name}, using basic evaluation setup")
            self.config = self._get_default_channel_config()
        else:
            # Parse YAML configuration
            try:
                self.config = yaml.safe_load(crew_config.config_yaml)
            except yaml.YAMLError as e:
                logger.error(f"Invalid YAML configuration for channel {channel.name}: {e}, using default")
                self.config = self._get_default_channel_config()

        # Build crew from configuration
        self.crew = self._create_crew_from_config()

    def _get_default_channel_config(self) -> Dict[str, Any]:
        """Get a basic default configuration for channel evaluation."""
        return {
            'agents': [
                {
                    'role': f'{self.channel.name} Channel Specialist',
                    'goal': f'Evaluate content suitability for {self.channel.name} channel and determine relevance score',
                    'backstory': f"""You are an expert in {self.channel.name} channel with deep understanding of its audience,
                    content preferences, and engagement patterns. You know exactly what content performs well on this channel.

                    Channel description: {self.channel.description_by_user}
                    Channel language: {self.channel.language}
                    Target persona: {self.channel.target_persona}
                    Channel type: {self.channel.channel_type.name if self.channel.channel_type else 'General'}""",
                    'verbose': True,
                    'allow_delegation': False
                }
            ],
            'tasks': [
                {
                    'description': f"""Evaluate and score the processed content for {self.channel.name} channel:

                    1. Assess channel fit and relevance (1-10 score)
                    2. Check language compatibility with channel language: {self.channel.language}
                    3. Evaluate alignment with target persona: {self.channel.target_persona or 'General audience'}
                    4. Consider channel description: {self.channel.description_by_user}
                    5. Provide specific reasoning for the score

                    Content to evaluate: {{content}}
                    Enhanced content variations: {{enhanced_content}}
                    Source information: {{source_info}}
                    """,
                    'expected_output': """Channel evaluation in JSON format:
                    {
                        "relevance_score": 8,
                        "language_acceptability_score": 10,
                        "final_affinity_score": 8.5,
                        "reasoning": "Detailed explanation of scoring",
                        "recommendation": "publish/skip/review",
                        "suggested_adaptations": ["adaptation1", "adaptation2"]
                    }""",
                    'agent': f'{self.channel.name} Channel Specialist'
                }
            ]
        }

    def _get_agent_llm(self, agent_config: Dict[str, Any]) -> Any:
        """
        Gets the LLM for a specific agent based on its configuration.
        Uses agent-specific config if available, otherwise falls back to default LLM.
        """
        llm_config = agent_config.get('llm_config', {})
        if llm_config and llm_config.get('provider_name'):
            return get_llm(
                provider_name=llm_config.get('provider_name'),
                model_name=llm_config.get('model_name')
            )
        return self.default_llm

    def _create_crew_from_config(self) -> Crew:
        """Dynamically build a Crew from database YAML configuration."""
        agents_map = {}

        # Create agents
        for agent_config in self.config.get('agents', []):
            agent_llm = self._get_agent_llm(agent_config)

            agent = Agent(
                role=agent_config['role'],
                goal=agent_config['goal'],
                backstory=agent_config['backstory'],
                verbose=agent_config.get('verbose', True),
                allow_delegation=agent_config.get('allow_delegation', False),
                llm=agent_llm
            )
            agents_map[agent_config['role']] = agent

        # Create tasks
        tasks = []
        for task_config in self.config.get('tasks', []):
            # Get the agent for this task
            agent_role = task_config['agent']
            if agent_role not in agents_map:
                raise ValueError(f"Agent '{agent_role}' not found for task '{task_config.get('description', 'Unknown')}'")

            task = Task(
                description=task_config['description'],
                expected_output=task_config['expected_output'],
                agent=agents_map[agent_role]
            )
            tasks.append(task)

        # Create and return Crew
        crew = Crew(
            agents=list(agents_map.values()),
            tasks=tasks,
            verbose=True,
            process=Process.sequential
        )
        return crew

    def evaluate_content(self, processed_content: Dict[str, Any], content_item: ContentItem) -> Dict[str, Any]:
        """
        Evaluate processed content for this specific channel.

        Args:
            processed_content: Result from GlobalContentPreprocessingCrew
            content_item: Original ContentItem for context

        Returns:
            Dict containing channel-specific evaluation and affinity scores
        """
        try:
            # Get the actual content text, not raw JSON
            content_text = content_item.raw_content or ''

            # If content looks like JSON (starts with '{'), try to parse it
            if content_text.strip().startswith('{'):
                try:
                    import json
                    parsed_json = json.loads(content_text)
                    # If it's a Nostr event, extract the content field
                    if 'content' in parsed_json:
                        content_text = parsed_json['content']
                        # Replace literal \n with actual newlines
                        content_text = content_text.replace('\\n', '\n')
                except json.JSONDecodeError:
                    # If parsing fails, use the original text
                    pass

            # Prepare inputs for the crew - use enhanced content from ContentItem
            crew_inputs = {
                'content': content_text,
                'enhanced_content': {
                    'short': content_item.enhanced_short or processed_content.get('enhanced_short', ''),
                    'medium': content_item.enhanced_medium or processed_content.get('enhanced_medium', ''),
                    'long': content_item.enhanced_long or processed_content.get('enhanced_long', '')
                },
                'source_info': f"Distance: {content_item.initial_distance}, Source: {content_item.source.identifier if content_item.source else 'Unknown'}",
                'analysis': processed_content.get('analysis', {}),
                'link_url': content_item.link_url or '',
                'quality_score': content_item.quality_score or processed_content.get('quality_score', 0)
            }

            # Execute the crew
            logger.info(f"Evaluating content item {content_item.id} for channel {self.channel.name}")
            result = self.crew.kickoff(inputs=crew_inputs)

            # Parse the result - expecting JSON format
            try:
                if hasattr(result, 'raw'):
                    result_text = result.raw
                else:
                    result_text = str(result)

                # Try to parse as JSON
                parsed_result = json.loads(result_text)

                # Extract structured data for database storage
                return {
                    'relevance_score': parsed_result.get('relevance_score', 0),
                    'language_acceptability_score': parsed_result.get('language_acceptability_score', 0),
                    'final_affinity_score': parsed_result.get('final_affinity_score', 0),
                    'reasoning': parsed_result.get('reasoning', ''),
                    'recommendation': parsed_result.get('recommendation', 'review'),
                    'suggested_adaptations': parsed_result.get('suggested_adaptations', []),
                    'evaluation_result_json': result_text,
                    'status': 'completed'
                }

            except json.JSONDecodeError:
                # If not JSON, store raw result and use default scores
                logger.warning(f"Channel evaluation result for content item {content_item.id} and channel {self.channel.name} is not valid JSON")
                return {
                    'relevance_score': 5,  # Default middle score
                    'language_acceptability_score': 5,
                    'final_affinity_score': 5,
                    'reasoning': 'Unable to parse structured evaluation result',
                    'recommendation': 'review',
                    'suggested_adaptations': [],
                    'evaluation_result_json': result_text,
                    'status': 'completed_with_warnings'
                }

        except Exception as e:
            logger.error(f"Error evaluating content item {content_item.id} for channel {self.channel.name}: {e}")
            return {
                'relevance_score': 0,
                'language_acceptability_score': 0,
                'final_affinity_score': 0,
                'reasoning': f'Evaluation failed: {str(e)}',
                'recommendation': 'skip',
                'suggested_adaptations': [],
                'evaluation_result_json': json.dumps({'error': str(e)}),
                'status': 'error'
            }


class CrewService:
    """
    Main service for managing all CrewAI operations.
    Provides database-driven crew management for both global and channel-specific processing.
    """

    def __init__(self):
        """Initialize the crew service."""
        self.global_crew = None
        self.channel_crews = {}

    def get_global_crew(self, llm_provider: Optional[str] = None, llm_model: Optional[str] = None) -> GlobalContentPreprocessingCrew:
        """Get or create global preprocessing crew from database configuration."""
        return GlobalContentPreprocessingCrew(
            default_llm_provider=llm_provider,
            default_llm_model=llm_model
        )

    def get_channel_crew(self, channel: Channel, llm_provider: Optional[str] = None, llm_model: Optional[str] = None) -> ChannelContentEvaluationCrew:
        """Get or create channel-specific crew from database configuration."""
        crew_key = f"{channel.id}_{llm_provider}_{llm_model}"
        if crew_key not in self.channel_crews:
            self.channel_crews[crew_key] = ChannelContentEvaluationCrew(
                channel=channel,
                default_llm_provider=llm_provider,
                default_llm_model=llm_model
            )
        return self.channel_crews[crew_key]

    def process_content_item(self, content_item: ContentItem, target_channels: Optional[List[Channel]] = None) -> Dict[str, Any]:
        """
        Process a content item through the full pipeline:
        1. Global preprocessing - analyze and enhance content
        2. Channel-specific evaluation - determine channel fit and affinity scores
        3. Store results in database

        Args:
            content_item: ContentItem to process
            target_channels: List of channels to evaluate for, or None for all active channels

        Returns:
            Dict containing all processing results
        """
        from lievik.models import ChannelContentAffinity

        results = {
            'content_item_id': content_item.id,
            'processing_started': datetime.utcnow(),
            'global_processing': None,
            'channel_evaluations': [],
            'status': 'processing'
        }

        try:
            # Step 1: Global preprocessing
            logger.info(f"Starting global preprocessing for content item {content_item.id}")
            global_crew = self.get_global_crew()
            global_result = global_crew.process_content(content_item)
            results['global_processing'] = global_result

            # Update ContentItem with enhanced content from crew processing
            content_item.crew_result_json = global_result.get('crew_result_json', '')
            content_item.enhanced_short = global_result.get('enhanced_short', '')
            content_item.enhanced_medium = global_result.get('enhanced_medium', '')
            content_item.enhanced_long = global_result.get('enhanced_long', '')
            content_item.quality_score = global_result.get('quality_score', 0)

            # Update ProcessedWebContent with web-specific enhanced content
            if content_item.processed_web_content:
                for web_content in content_item.processed_web_content:
                    # Check if this was the web content analyzed by the crew
                    if web_content.id == global_result.get('web_content_id'):
                        # Save the web-specific enhancements
                        web_content.crew_result_json = global_result.get('crew_result_json', '')
                        web_content.enhanced_short = global_result.get('web_enhanced_short', '')
                        web_content.enhanced_medium = global_result.get('web_enhanced_medium', '')
                        web_content.enhanced_long = global_result.get('web_enhanced_long', '')
                        # Update the summary if crew provided a better one
                        if global_result.get('web_summary'):
                            web_content.summary_text = global_result.get('web_summary', '')
                        logger.info(f"Updated ProcessedWebContent {web_content.id} with crew enhancements")

            if global_result.get('analysis', {}).get('error'):
                results['status'] = 'failed_global'
                results['error'] = global_result['analysis']['error']
                logger.warning(f"Global preprocessing failed for content item {content_item.id}")
                return results

            # Step 2: Channel-specific evaluation
            if target_channels is None:
                # Get all active channels for the user
                target_channels = Channel.query.filter_by(
                    user_id=content_item.source.user_id,
                    is_active=True
                ).all()

            logger.info(f"Evaluating content item {content_item.id} for {len(target_channels)} channels")

            for channel in target_channels:
                try:
                    channel_crew = self.get_channel_crew(channel)
                    channel_result = channel_crew.evaluate_content(global_result, content_item)

                    # Store/update channel affinity in database
                    affinity = ChannelContentAffinity.query.filter_by(
                        content_item_id=content_item.id,
                        channel_id=channel.id
                    ).first()

                    if not affinity:
                        affinity = ChannelContentAffinity(
                            content_item_id=content_item.id,
                            channel_id=channel.id
                        )
                        db.session.add(affinity)

                    # Update affinity scores and status
                    affinity.relevance_score = channel_result.get('relevance_score', 0)
                    affinity.language_acceptability_score = channel_result.get('language_acceptability_score', 0)
                    affinity.final_affinity_score = channel_result.get('final_affinity_score', 0)
                    affinity.status = channel_result.get('recommendation', 'review')

                    channel_result['channel_id'] = channel.id
                    channel_result['channel_name'] = channel.name
                    results['channel_evaluations'].append(channel_result)

                except Exception as e:
                    logger.error(f"Failed to evaluate content for channel {channel.name}: {e}")
                    results['channel_evaluations'].append({
                        'channel_id': channel.id,
                        'channel_name': channel.name,
                        'status': 'error',
                        'error': str(e)
                    })

            # Don't commit here - let the caller handle the transaction
            results['processing_completed'] = datetime.utcnow()
            results['status'] = 'completed'

            logger.info(f"Successfully processed content item {content_item.id} for {len(target_channels)} channels")
            return results

        except Exception as e:
            logger.error(f"Error processing content item {content_item.id}: {e}")
            results['status'] = 'error'
            results['error'] = str(e)
            return results
