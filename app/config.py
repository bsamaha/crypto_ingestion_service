from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, field_validator, ValidationInfo
from typing import List, Optional, Any
from functools import lru_cache
import json
import os
from enum import Enum

class LogLevel(str, Enum):
    """Valid logging levels"""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"

class Channel(str, Enum):
    """Valid WebSocket channels"""
    CANDLES = "candles"
    HEARTBEATS = "heartbeats"
    TICKER = "ticker"

class Settings(BaseSettings):
    """Application configuration
    
    This class handles all configuration for the application, including:
    - API credentials
    - WebSocket settings
    - Service configuration
    - Feature flags
    - Kafka configuration
    
    Configuration is loaded from environment variables or .env file
    """
    
    # API Credentials
    COINBASE_API_KEY: str = Field(
        description="Coinbase API Key from Advanced Trade"
    )
    COINBASE_API_SECRET: str = Field(
        description="Coinbase API Secret from Advanced Trade"
    )
    
    # WebSocket Configuration
    PRODUCT_IDS: List[str] = Field(
        default_factory=lambda: ["BTC-USD", "ETH-USD"],
        description="Trading pairs to monitor"
    )
    CHANNELS: List[str] = Field(
        default_factory=lambda: ["candles", "heartbeats"],
        description="WebSocket channels to subscribe to"
    )
    WS_TIMEOUT: int = Field(
        default=30,
        ge=1,
        le=300,
        description="WebSocket timeout in seconds"
    )
    WS_MAX_SIZE: int = Field(
        default=1048576,
        description="Maximum WebSocket message size"
    )
    RECONNECT_DELAY: int = Field(
        default=20,
        ge=1,
        le=300,
        description="Delay between reconnection attempts"
    )
    
    # Service Configuration
    LOG_LEVEL: LogLevel = Field(
        default=LogLevel.INFO,
        description="Logging level"
    )
    METRICS_PORT: int = Field(
        default=8000,
        ge=1024,
        le=65535,
        description="Port for health and metrics endpoints"
    )
    
    # Feature Flags
    ENABLE_HEARTBEAT: bool = Field(
        default=True,
        description="Enable/disable heartbeat monitoring"
    )
    ENABLE_DEBUG_METRICS: bool = Field(
        default=False,
        description="Enable additional debug metrics"
    )

    # Kafka Configuration
    KAFKA_BOOTSTRAP_SERVERS: str = Field(
        default="localhost:9092",
        description="Kafka bootstrap servers"
    )
    KAFKA_ENABLED: bool = Field(
        default=False,
        description="Enable/disable Kafka message publishing"
    )
    KAFKA_TOPIC: str = Field(
        default="coinbase.candles",
        description="Kafka topic for publishing candle data"
    )
    
    model_config = SettingsConfigDict(
        env_file='.env',
        env_file_encoding='utf-8',
        case_sensitive=True,
        env_prefix='',
        extra='ignore'
    )
    



    @field_validator('CHANNELS')
    @classmethod  # Required for field_validator
    def validate_channels(cls, v):
        """Ensure all channels are valid"""
        valid_channels = set(c.value for c in Channel)
        invalid_channels = set(v) - valid_channels
        if invalid_channels:
            raise ValueError(f"Invalid channels: {invalid_channels}. Valid channels are: {valid_channels}")
        return v
    
    @field_validator('PRODUCT_IDS')
    @classmethod
    def validate_product_ids(cls, v):
        """Ensure product IDs are properly formatted"""
        if not v:
            return ["BTC-USD", "ETH-USD"]
        for product_id in v:
            if not product_id or '-' not in product_id:
                raise ValueError(f"Invalid product ID format: {product_id}. Expected format: BASE-QUOTE (e.g., BTC-USD)")
        return v
    
    @field_validator('KAFKA_TOPIC')
    @classmethod
    def validate_kafka_topic(cls, v):
        """Ensure Kafka topic is properly formatted"""
        if not v or not isinstance(v, str):
            raise ValueError("Kafka topic must be a non-empty string")
        if len(v) > 249:  # Kafka has a limit of 249 characters for topic names
            raise ValueError("Kafka topic name too long (max 249 characters)")
        if not all(c.isalnum() or c in ('-', '_', '.') for c in v):
            raise ValueError("Kafka topic can only contain alphanumeric characters, '.', '-', and '_'")
        return v
    
    @field_validator('COINBASE_API_KEY', 'COINBASE_API_SECRET')
    @classmethod
    def validate_api_credentials(cls, v: str, info: ValidationInfo) -> str:
        """Ensure API credentials are properly formatted"""
        if info.field_name == 'COINBASE_API_KEY':
            # Clean and validate API key
            cleaned = ''.join(v.split())
            # Allow path-like format with slashes and dashes
            if not all(c in '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-/=' for c in cleaned):
                raise ValueError("API key contains invalid characters")
            if len(cleaned) < 10:
                raise ValueError("API key seems too short")
            return cleaned
        else:  # COINBASE_API_SECRET
            # Handle EC private key
            # Replace literal \n with newlines for proper PEM format
            normalized = v.replace('\\n', '\n')
            if not normalized.startswith('-----BEGIN EC PRIVATE KEY-----'):
                raise ValueError("API secret must be an EC private key")
            if not normalized.endswith('-----END EC PRIVATE KEY-----\n'):
                raise ValueError("API secret must be a properly formatted EC private key")
            return normalized
    
    def model_post_init(self, *args, **kwargs):
        """Post-initialization processing"""
        super().model_post_init(*args, **kwargs)

@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance"""
    api_key = os.getenv("COINBASE_API_KEY")
    api_secret = os.getenv("COINBASE_API_SECRET")
    
    if not api_key or not api_secret:
        raise ValueError("COINBASE_API_KEY and COINBASE_API_SECRET must be set")
        
    return Settings(
        COINBASE_API_KEY=api_key,
        COINBASE_API_SECRET=api_secret
    )

def get_settings_dict() -> dict:
    """Get settings as a dictionary (useful for debugging)
    
    Returns:
        dict: Configuration as a dictionary with sensitive data redacted
    """
    settings = get_settings()
    settings_dict = settings.model_dump()
    
    # Redact sensitive information
    settings_dict['COINBASE_API_KEY'] = '***REDACTED***'
    settings_dict['COINBASE_API_SECRET'] = '***REDACTED***'

    
    return settings_dict