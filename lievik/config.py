import os
from datetime import timedelta


class Config:
    """Base configuration."""
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # CrewAI Configuration
    CREWAI_DISABLE_TELEMETRY = 'true'
    OTEL_SDK_DISABLED = 'true'

    # LLM API Keys (optional, can be set per crew configuration)
    GEMINI_API_KEY = os.getenv('GEMINI_API_KEY')
    VENICE_API_KEY = os.getenv('VENICE_API_KEY')
    OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')

    # Content Ingestion Settings
    INGESTION_INTERVAL_HOURS = int(os.getenv('INGESTION_INTERVAL_HOURS', '1'))
    MAX_CONTENT_AGE_DAYS = int(os.getenv('MAX_CONTENT_AGE_DAYS', '30'))


class DevelopmentConfig(Config):
    """Development configuration."""
    DEBUG = True

    # Database URL - defaults to SQLite for development
    SQLALCHEMY_DATABASE_URI = os.getenv(
        'DATABASE_URL',
        'sqlite:///lievik_dev.db'
    )


class ProductionConfig(Config):
    """Production configuration."""
    DEBUG = False

    # Database URL - should be set in production environment
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL')

    if not SQLALCHEMY_DATABASE_URI:
        raise ValueError("DATABASE_URL environment variable is required for production")


class TestingConfig(Config):
    """Testing configuration."""
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False
