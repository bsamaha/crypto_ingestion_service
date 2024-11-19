import pytest
from app.config import Settings, get_settings
import os
from unittest.mock import patch

def test_settings_default_values():
    """Test that Settings has correct default values"""
    settings = Settings(
        COINBASE_API_KEY="test_key",
        COINBASE_API_SECRET="test_secret"
    )
    assert settings.WS_TIMEOUT == 30
    assert settings.WS_MAX_SIZE == 1048576
    assert settings.PRODUCT_IDS == ["BTC-USD", "ETH-USD"]
    assert settings.CHANNELS == ["candles", "heartbeats"]

def test_settings_environment_override():
    """Test that environment variables override defaults"""
    env_vars = {
        "COINBASE_API_KEY": "env_key",
        "COINBASE_API_SECRET": "env_secret",
        "LOG_LEVEL": "DEBUG"
    }
    
    with patch.dict(os.environ, env_vars, clear=True):
        settings = Settings(
            COINBASE_API_KEY=env_vars["COINBASE_API_KEY"],
            COINBASE_API_SECRET=env_vars["COINBASE_API_SECRET"]
        )
        assert settings.COINBASE_API_KEY == "env_key"
        assert settings.COINBASE_API_SECRET == "env_secret"
        assert settings.LOG_LEVEL == "DEBUG"

def test_settings_post_init():
    """Test that API credentials are properly copied"""
    settings = Settings(
        COINBASE_API_KEY="test_key",
        COINBASE_API_SECRET="test_secret"
    )
    assert settings.COINBASE_API_KEY == "test_key"
    assert settings.COINBASE_API_SECRET == "test_secret"

def test_get_settings_cache():
    """Test that get_settings caches its result"""
    with patch.dict(os.environ, {
        "COINBASE_API_KEY": "test_key",
        "COINBASE_API_SECRET": "test_secret"
    }):
        first = get_settings()
        second = get_settings()
        assert first is second 