import pytest
from app.utils.logging_utils import setup_logging, log_candle_json
import json
import logging
import sys
from typing import Dict, Any
from unittest.mock import Mock, patch

@pytest.fixture
def mock_logger() -> Mock:
    """Create a mock logger for testing"""
    mock = Mock(spec=logging.Logger)
    mock.info = Mock()  # Add mock methods
    mock.error = Mock()
    mock.debug = Mock()
    return mock

def test_log_candle_json_format(
    sample_candle_data: Dict[str, str],
    mock_logger: Mock
) -> None:
    """Test that candle data is properly formatted for logging"""
    # Add required fields to sample data if missing
    test_data = sample_candle_data.copy()
    if 'start' not in test_data:
        test_data['start'] = "1637001600"
    if 'product_id' not in test_data:
        test_data['product_id'] = "BTC-USD"
    
    log_candle_json(test_data, mock_logger)
    
    # Verify the logger was called
    mock_logger.info.assert_called_once()
    
    # Parse the logged JSON
    call_args = mock_logger.info.call_args[0][0]
    logged_data = json.loads(call_args)
    
    # Verify required fields
    assert "event_time" in logged_data
    assert "symbol" in logged_data
    assert "open_price" in logged_data
    assert logged_data["symbol"] == test_data["product_id"]
    assert logged_data["open_price"] == test_data["open"]

def test_log_candle_json_error_handling(mock_logger: Mock) -> None:
    """Test error handling in log_candle_json"""
    invalid_data: Dict[str, Any] = {"invalid": "data"}
    log_candle_json(invalid_data, mock_logger)
    
    # Verify error was logged
    mock_logger.error.assert_called_once()
    
    # Verify error message
    error_msg = mock_logger.error.call_args[0][0]
    assert "Error formatting candle data" in error_msg

def test_setup_logging(temp_log_file: str) -> None:
    """Test logging setup"""
    setup_logging("DEBUG")
    logger = logging.getLogger()
    
    # Verify logger configuration
    assert logger.level == logging.DEBUG
    
    # Verify we have a StreamHandler for stdout
    handlers = [h for h in logger.handlers if isinstance(h, logging.StreamHandler)]
    assert len(handlers) > 0
    
    # Verify structlog configuration
    handler = handlers[0]
    # Check if handler is writing to stdout
    assert handler.stream is sys.stdout  # type: ignore
    
    # Verify no FileHandlers are present
    assert not any(isinstance(h, logging.FileHandler) for h in logger.handlers)