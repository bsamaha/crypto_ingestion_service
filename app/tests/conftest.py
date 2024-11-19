import pytest
from unittest.mock import Mock, patch
from app.config import Settings, LogLevel
import json
import logging
import tempfile
import os
import asyncio
import sys
import platform
from typing import Generator, Any
from pytest import FixtureRequest, MonkeyPatch

def pytest_configure(config):
    """Configure pytest"""
    if platform.system() == 'Windows':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    
    # Suppress logging during tests
    logging.getLogger('backoff').setLevel(logging.ERROR)
    logging.getLogger('websockets').setLevel(logging.ERROR)
    logging.getLogger('httpx').setLevel(logging.ERROR)

@pytest.fixture(autouse=True)
def suppress_logging():
    """Suppress logging for specific tests"""
    root_logger = logging.getLogger()
    previous_level = root_logger.getEffectiveLevel()
    root_logger.setLevel(logging.ERROR)
    yield
    root_logger.setLevel(previous_level)

@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session"""
    if sys.platform == 'win32':
        loop = asyncio.new_event_loop()
        yield loop
        loop.close()
    else:
        loop = asyncio.get_event_loop_policy().new_event_loop()
        yield loop
        loop.close()

@pytest.fixture(autouse=True)
async def cleanup_tasks():
    """Clean up any pending tasks after each test"""
    yield
    for task in asyncio.all_tasks():
        if task is not asyncio.current_task():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

@pytest.fixture
def mock_settings() -> Settings:
    return Settings(
        COINBASE_API_KEY="test_key",
        COINBASE_API_SECRET="test_secret",
        PRODUCT_IDS=["BTC-USD"],
        CHANNELS=["candles"],
        WS_TIMEOUT=30,
        WS_MAX_SIZE=1048576,
        RECONNECT_DELAY=1,
        LOG_LEVEL=LogLevel.INFO,
        METRICS_PORT=8000
    )

@pytest.fixture
def sample_candle_data():
    return {
        "product_id": "BTC-USD",
        "start": "1637001600",
        "open": "60000.00",
        "high": "61000.00",
        "low": "59000.00",
        "close": "60500.00",
        "volume": "100.00"
    }

@pytest.fixture
def mock_ws_client():
    with patch('app.services.websocket_service.WSClient') as mock_client:
        instance = Mock()
        mock_client.return_value = instance
        instance.open = Mock()
        instance.close = Mock()
        yield instance

@pytest.fixture
def temp_log_file():
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        yield tmp.name
    os.unlink(tmp.name)

@pytest.fixture
def mock_logger():
    return Mock(spec=logging.Logger)

@pytest.fixture
def some_fixture(request: FixtureRequest) -> Generator[str, None, None]:
    test_value = "test"
    yield test_value

@pytest.fixture()
def settings_fixture(monkeypatch: MonkeyPatch) -> Generator[Settings, None, None]:
    """Test settings fixture"""
    settings = Settings(
        COINBASE_API_KEY="test_key",
        COINBASE_API_SECRET="test_secret"
    )
    yield settings 