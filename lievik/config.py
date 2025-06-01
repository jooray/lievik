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
    VENICE_API_KEY = os.getenv('VENICE_API_KEY')
    OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')

    # LLM Provider Configuration
    LLM_PROVIDERS = {
        'ollama': {
            'api_base': os.getenv('OLLAMA_API_BASE', 'http://localhost:11434/v1'), # Default for local Ollama
            'default_model': os.getenv('OLLAMA_DEFAULT_MODEL', 'llama3')
        },
        'venice': {
            'api_base': os.getenv('VENICE_API_BASE', 'https://api.venice.ai/api/v1'), # As per spec
            'api_key_env': 'VENICE_API_KEY', # Environment variable name for the key
            'default_model': os.getenv('VENICE_DEFAULT_MODEL', 'openai/qwen3-235b:strip_thinking_response=true')  # Add openai/ prefix for LiteLLM
        },
        'openai': {
            'api_base': os.getenv('OPENAI_API_BASE', 'https://api.openai.com/v1'),
            'api_key_env': 'OPENAI_API_KEY',
            'default_model': os.getenv('OPENAI_DEFAULT_MODEL', 'gpt-4o')
        }
        # Add other providers as needed
    }

    # Default LLM provider and model to use if not specified at agent level
    DEFAULT_LLM_PROVIDER = os.getenv('DEFAULT_LLM_PROVIDER', 'venice') # e.g., 'ollama', 'venice'
    DEFAULT_LLM_MODEL = os.getenv('DEFAULT_LLM_MODEL', None) # If None, uses provider's default_model

    # Content Ingestion Settings
    INGESTION_INTERVAL_HOURS = int(os.getenv('INGESTION_INTERVAL_HOURS', '1'))
    MAX_CONTENT_AGE_DAYS = int(os.getenv('MAX_CONTENT_AGE_DAYS', '30'))

    # Enhanced Scheduler Configuration for Task 2.4
    INGESTION_SCHEDULE_TYPE = os.getenv('INGESTION_SCHEDULE_TYPE', 'interval')  # 'interval' or 'cron'
    INGESTION_CRON_SCHEDULE = os.getenv('INGESTION_CRON_SCHEDULE', '0 */1 * * *')  # Default: every hour
    INGESTION_MAX_INSTANCES = int(os.getenv('INGESTION_MAX_INSTANCES', '1'))
    INGESTION_COALESCE = os.getenv('INGESTION_COALESCE', 'true').lower() == 'true'
    INGESTION_MISFIRE_GRACE_TIME = int(os.getenv('INGESTION_MISFIRE_GRACE_TIME', '300'))  # 5 minutes

    # Content Processing Configuration
    PROCESS_CONTENT_IMMEDIATELY = os.getenv('PROCESS_CONTENT_IMMEDIATELY', 'true').lower() == 'true'
    CREW_PROCESSING_TIMEOUT = int(os.getenv('CREW_PROCESSING_TIMEOUT', '300'))  # 5 minutes
    CREW_PROCESSING_RETRY_ATTEMPTS = int(os.getenv('CREW_PROCESSING_RETRY_ATTEMPTS', '2'))

    # APScheduler Configuration
    SCHEDULER_API_ENABLED = True
    SCHEDULER_TIMEZONE = os.getenv('SCHEDULER_TIMEZONE', 'UTC')
    SCHEDULER_JOB_DEFAULTS = {
        'coalesce': INGESTION_COALESCE,
        'max_instances': INGESTION_MAX_INSTANCES,
        'misfire_grace_time': INGESTION_MISFIRE_GRACE_TIME
    }


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
