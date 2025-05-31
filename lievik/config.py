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

    # LLM Provider Configuration
    LLM_PROVIDERS = {
        'ollama': {
            'api_base': os.getenv('OLLAMA_API_BASE', 'http://localhost:11434/v1'), # Default for local Ollama
            'default_model': os.getenv('OLLAMA_DEFAULT_MODEL', 'llama3')
        },
        'venice': {
            'api_base': os.getenv('VENICE_API_BASE', 'https://api.venice.ai/v1'), # As per spec
            'api_key_env': 'VENICE_API_KEY', # Environment variable name for the key
            'default_model': os.getenv('VENICE_DEFAULT_MODEL', 'qwen3-235b:strip_thinking_response=true')
        },
        'openai': {
            'api_base': os.getenv('OPENAI_API_BASE', 'https://api.openai.com/v1'),
            'api_key_env': 'OPENAI_API_KEY',
            'default_model': os.getenv('OPENAI_DEFAULT_MODEL', 'gpt-4o')
        },
        'gemini': { # Added based on existing API key
            'api_key_env': 'GEMINI_API_KEY',
            'default_model': os.getenv('GEMINI_DEFAULT_MODEL', 'gemini-1.5-pro-latest')
        }
        # Add other providers as needed
    }

    # Default LLM provider and model to use if not specified at agent level
    DEFAULT_LLM_PROVIDER = os.getenv('DEFAULT_LLM_PROVIDER', 'venice') # e.g., 'ollama', 'venice'
    DEFAULT_LLM_MODEL = os.getenv('DEFAULT_LLM_MODEL') # If None, uses provider's default_model

    # Content Ingestion Settings
    INGESTION_INTERVAL_HOURS = int(os.getenv('INGESTION_INTERVAL_HOURS', '1'))
    MAX_CONTENT_AGE_DAYS = int(os.getenv('MAX_CONTENT_AGE_DAYS', '30'))

    # APScheduler Configuration
    SCHEDULER_API_ENABLED = True
    SCHEDULER_TIMEZONE = os.getenv('SCHEDULER_TIMEZONE', 'UTC')


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
