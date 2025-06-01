import os
from crewai import LLM
from flask import current_app

# Ensure telemetry is disabled as early as possible
# These are also in config.py, but setting them via os.environ ensures CrewAI sees them
os.environ['CREWAI_DISABLE_TELEMETRY'] = 'true'
os.environ['OTEL_SDK_DISABLED'] = 'true'

def get_llm(provider_name: str = None, model_name: str = None, api_key: str = None) -> LLM:
    """
    Initializes and returns a CrewAI LLM instance based on the provider and model.
    Uses default configuration from Flask app if provider_name or model_name are not specified.
    Prioritizes specific LLM classes from crewai.llms for better compatibility.

    Args:
        provider_name (str, optional): The name of the LLM provider (e.g., 'ollama', 'venice', 'openai', 'gemini').
                                       Defaults to the app's DEFAULT_LLM_PROVIDER.
        model_name (str, optional): The specific model name to use.
                                    Defaults to the app's DEFAULT_LLM_MODEL, then provider's default_model.
        api_key (str, optional): The API key, if required and not already set in environment.

    Returns:
        LLM: An instance of a CrewAI LLM.

    Raises:
        ValueError: If the provider is not configured, required API keys are missing, or model name is missing.
    """
    config = current_app.config

    effective_provider_name = provider_name or config['DEFAULT_LLM_PROVIDER']
    provider_config = config['LLM_PROVIDERS'].get(effective_provider_name)

    if not provider_config:
        raise ValueError(f"LLM provider '{effective_provider_name}' is not configured.")

    # Determine effective model name with proper fallback logic
    if model_name:
        # Explicit model name provided
        effective_model_name = model_name
    elif config.get('DEFAULT_LLM_MODEL'):
        # Use global default if set
        effective_model_name = config['DEFAULT_LLM_MODEL']
    else:
        # Fall back to provider's default model
        effective_model_name = provider_config.get('default_model')

    if not effective_model_name:
        raise ValueError(
            f"No model name specified and no default model configured for provider '{effective_provider_name}' or globally."
        )

    # Common parameters for generic LLM, might be overridden by specific LLMs
    llm_params = {"model_name": effective_model_name} # CrewAI's generic LLM often uses model_name

    # Handle API keys
    actual_api_key = api_key # Use provided api_key first
    if not actual_api_key and provider_config.get('api_key_env'):
        actual_api_key = os.getenv(provider_config['api_key_env'])

    if provider_config.get('api_key_env') and not actual_api_key:
        # Only raise error if an API key was expected (api_key_env was set) but not found
        raise ValueError(
            f"API key for '{effective_provider_name}' (env var: {provider_config['api_key_env']}) not found and not provided directly."
        )

    # Instantiate specific LLM clients for better compatibility and feature access
    if effective_provider_name == 'ollama':
        return LLM(
            model=f"ollama/{effective_model_name}",
            base_url=provider_config.get('api_base', 'http://localhost:11434')
        )

    # For OpenAI and OpenAI-compatible APIs (like Venice)
    elif effective_provider_name in ['openai', 'venice']:
        llm_params = {
            "model": effective_model_name,
        }

        if actual_api_key:
            llm_params["api_key"] = actual_api_key

        api_base = provider_config.get('api_base')
        if api_base:
            llm_params["base_url"] = api_base

        # For Venice, ensure the model has openai/ prefix for LiteLLM compatibility
        if effective_provider_name == 'venice' and not effective_model_name.startswith('openai/'):
            llm_params["model"] = f"openai/{effective_model_name}"
            current_app.logger.info(f"Adding 'openai/' prefix to Venice model: {llm_params['model']}")

        return LLM(**llm_params)

    # For Gemini
    elif effective_provider_name == 'gemini':
        llm_params = {
            "model": f"gemini/{effective_model_name}",
        }

        if actual_api_key:
            llm_params["api_key"] = actual_api_key

        return LLM(**llm_params)

    else:
        # Fallback to generic LLM for other providers
        current_app.logger.warning(
            f"Provider '{effective_provider_name}' does not have a specific handler. "
            f"Using generic LLM configuration."
        )

        llm_params = {
            "model": effective_model_name,
        }
        if actual_api_key:
            llm_params["api_key"] = actual_api_key

        api_base = provider_config.get('api_base')
        if api_base:
            llm_params["base_url"] = api_base

        return LLM(**llm_params)

# Example of how an agent in crew_service.py might get a specific LLM:
# try:
#     # Agent wants to use a specific model from a specific provider
#     translator_llm = get_llm(provider_name='ollama', model_name='mistral-translate-sk')
# except ValueError as e:
#     current_app.logger.error(f"Could not get LLM for translator: {e}")
#     # Fallback to default LLM or handle error
#     translator_llm = get_llm() # Gets default
#
# And then:
# translator_agent = Agent(
#     role='Translator',
#     goal='Translate text to Slovak',
#     backstory='Expert in English-Slovak translation.',
#     llm=translator_llm, # Assign the specific LLM
#     ...
# )

# Ensure to remove or comment out the old implementation of get_llm

