from app.config import get_settings, get_settings_dict
import logging

logger = logging.getLogger(__name__)

def validate_configuration():
    """Validate application configuration on startup
    
    Raises:
        ValueError: If configuration is invalid
    """
    settings = get_settings()
    
    # Log configuration (with sensitive data redacted)
    logger.info("Starting with configuration:", extra={"config": get_settings_dict()})
    
    # Additional validation beyond Pydantic
    if len(settings.PRODUCT_IDS) == 0:
        raise ValueError("At least one product ID must be specified")
    
    if len(settings.CHANNELS) == 0:
        raise ValueError("At least one channel must be specified")
    
    if settings.ENABLE_HEARTBEAT and "heartbeats" not in settings.CHANNELS:
        raise ValueError("Heartbeat channel must be enabled when ENABLE_HEARTBEAT is true")
    
    logger.info("Configuration validation successful") 