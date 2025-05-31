from datetime import datetime
from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, Float, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from lievik.app import db
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash


class User(db.Model, UserMixin):
    """User model for authentication and ownership."""
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    username = Column(String(80), unique=True, nullable=False)
    email = Column(String(120), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)

    # Relationships
    sources = relationship('Source', backref='user', lazy=True)
    channels = relationship('Channel', backref='user', lazy=True)
    stories = relationship('Story', backref='user', lazy=True)
    notifications = relationship('Notification', backref='user', lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


class Source(db.Model):
    """Content sources (Nostr npubs, RSS feeds, etc.)."""
    __tablename__ = 'sources'

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    type = Column(String(20), nullable=False)  # 'nostr', 'rss', etc.
    identifier = Column(String(255), nullable=False)  # npub, URL, etc.
    base_distance = Column(Float, default=0.5)  # Base relevance distance
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)

    # Relationships
    content_items = relationship('ContentItem', backref='source', lazy=True)


class ContentItem(db.Model):
    """Raw ingested content items."""
    __tablename__ = 'content_items'

    id = Column(Integer, primary_key=True)
    source_id = Column(Integer, ForeignKey('sources.id'), nullable=False)
    original_id_on_source = Column(String(255))  # e.g., Nostr event ID
    raw_content = Column(Text)
    link_url = Column(String(500))
    publication_date = Column(DateTime)
    initial_distance = Column(Float)  # From source base_distance
    language_detected = Column(String(10))
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    processed_web_content_id = Column(Integer, ForeignKey('processed_web_content.id'))
    processed_web_content = relationship('ProcessedWebContent', backref='content_items')
    channel_affinities = relationship('ChannelContentAffinity', backref='content_item', lazy=True)
    notifications = relationship('Notification', backref='content_item', lazy=True)


class ProcessedWebContent(db.Model):
    """Scraped and summarized web pages."""
    __tablename__ = 'processed_web_content'

    id = Column(Integer, primary_key=True)
    original_url = Column(String(500), unique=True, nullable=False)
    title = Column(String(500))
    full_text = Column(Text)
    summary_text = Column(Text)
    processing_date = Column(DateTime, default=datetime.utcnow)
    language_detected = Column(String(10))


class ChannelType(db.Model):
    """Template types for channels."""
    __tablename__ = 'channel_types'

    id = Column(Integer, primary_key=True)
    name = Column(String(100), unique=True, nullable=False)  # e.g., "Course Newsletter", "Signal Group"
    description = Column(Text)
    default_crew_configuration_id = Column(Integer, ForeignKey('crew_configurations.id'))

    # Relationships
    channels = relationship('Channel', backref='channel_type', lazy=True)
    default_crew_configuration = relationship('CrewConfiguration', foreign_keys=[default_crew_configuration_id])


class CrewConfiguration(db.Model):
    """Stores YAML/JSON for CrewAI setups."""
    __tablename__ = 'crew_configurations'

    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    config_yaml = Column(Text, nullable=False)  # YAML configuration for CrewAI
    is_global = Column(Boolean, default=False)  # Global vs channel-specific
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    channels = relationship('Channel', backref='crew_configuration', lazy=True)


class Channel(db.Model):
    """User-defined marketing channels."""
    __tablename__ = 'channels'

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    name = Column(String(100), nullable=False)
    description_by_user = Column(Text)
    target_persona = Column(Text)
    channel_type_id = Column(Integer, ForeignKey('channel_types.id'), nullable=False)
    language = Column(String(10), nullable=False)  # e.g., 'en', 'sk'
    crew_configuration_id = Column(Integer, ForeignKey('crew_configurations.id'))
    icon_url = Column(String(500))
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)

    # Relationships
    channel_affinities = relationship('ChannelContentAffinity', backref='channel', lazy=True)
    stories = relationship('Story', backref='source_channel', lazy=True)
    channel_notifications = relationship('ChannelNotification', backref='channel', lazy=True)


class Story(db.Model):
    """User-curated and edited content blocks for reuse."""
    __tablename__ = 'stories'

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    original_content_item_id = Column(Integer, ForeignKey('content_items.id'))  # Optional
    title = Column(String(255), nullable=False)
    body_markdown = Column(Text, nullable=False)
    language = Column(String(10), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_edited_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    source_channel_id = Column(Integer, ForeignKey('channels.id'))  # Optional - where it was first curated

    # Relationships
    original_content_item = relationship('ContentItem', backref='stories')
    translated_stories = relationship('TranslatedStory', backref='original_story', lazy=True)


class TranslatedStory(db.Model):
    """Translations of stories for different languages."""
    __tablename__ = 'translated_stories'

    id = Column(Integer, primary_key=True)
    original_story_id = Column(Integer, ForeignKey('stories.id'), nullable=False)
    language = Column(String(10), nullable=False)
    translated_title = Column(String(255), nullable=False)
    translated_body_markdown = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (UniqueConstraint('original_story_id', 'language'),)


class ChannelContentAffinity(db.Model):
    """Stores AI evaluation results for content-channel pairs."""
    __tablename__ = 'channel_content_affinity'

    id = Column(Integer, primary_key=True)
    content_item_id = Column(Integer, ForeignKey('content_items.id'), nullable=False)
    channel_id = Column(Integer, ForeignKey('channels.id'), nullable=False)
    relevance_score = Column(Float)
    language_acceptability_score = Column(Float)
    final_affinity_score = Column(Float)
    status = Column(String(50), default='new')  # 'new', 'suggested', 'processed_for_newsletter_X'
    evaluated_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (UniqueConstraint('content_item_id', 'channel_id'),)


class Notification(db.Model):
    """Internal notifications for channels requiring proactive posting."""
    __tablename__ = 'notifications'

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    content_item_id = Column(Integer, ForeignKey('content_items.id'), nullable=False)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    is_processed = Column(Boolean, default=False)

    # Relationships
    channel_notifications = relationship('ChannelNotification', backref='notification', lazy=True)


class ChannelNotification(db.Model):
    """Links notifications to multiple relevant channels."""
    __tablename__ = 'channel_notifications'

    notification_id = Column(Integer, ForeignKey('notifications.id'), primary_key=True)
    channel_id = Column(Integer, ForeignKey('channels.id'), primary_key=True)
