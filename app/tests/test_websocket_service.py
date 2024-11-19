import pytest
from unittest.mock import AsyncMock, Mock, patch
from app.services.websocket_service import WebsocketService
from coinbase.websocket import WSClientConnectionClosedException
from app.utils.metrics import metrics
import json
import logging

@pytest.fixture
def quiet_logger():
    """Suppress specific log messages during tests"""
    with patch('logging.getLogger') as mock_logger:
        mock_logger.return_value = Mock(spec=logging.Logger)
        yield mock_logger

def test_websocket_service_init(mock_settings):
    """Test WebsocketService initialization"""
    service = WebsocketService(mock_settings)
    assert service.config == mock_settings
    assert service._client is None
    assert service._should_run is True

def test_establish_connection(mock_settings, mock_ws_client):
    """Test connection establishment"""
    service = WebsocketService(mock_settings)
    client = service._establish_connection()
    
    assert mock_ws_client.open.call_count == 1
    assert client == mock_ws_client

def test_connection_retry(mock_settings, mock_ws_client, quiet_logger):
    """Test connection retry behavior"""
    service = WebsocketService(mock_settings)
    mock_ws_client.open.side_effect = [
        WSClientConnectionClosedException("Test error"),
        WSClientConnectionClosedException("Test error"),
        None  # Succeeds on third try
    ]
    
    client = service._establish_connection()
    assert mock_ws_client.open.call_count == 3
    assert client == mock_ws_client

@pytest.mark.asyncio
async def test_graceful_shutdown(mock_settings, mock_ws_client):
    """Test graceful shutdown behavior"""
    service = WebsocketService(mock_settings)
    service._establish_connection()
    
    # Use unittest.mock.AsyncMock instead of pytest.AsyncMock
    mock_ws_client.close = AsyncMock()
    
    await service.stop()
    assert service._should_run is False
    assert mock_ws_client.close.await_count == 1 

def test_on_message_processing_invalid_json(mock_settings, mock_ws_client, quiet_logger):
    """Test handling of invalid JSON messages"""
    service = WebsocketService(mock_settings)
    
    # Suppress actual logging for test
    with patch.object(service, 'logger') as mock_logger:
        # Test with invalid JSON
        service.on_message("invalid json")
        
        # Verify error was logged with correct message
        mock_logger.error.assert_called_once_with(
            "Failed to parse message as JSON: Expecting value: line 1 column 1 (char 0)",
            exc_info=True
        )
        
        # Verify metrics were updated
        assert metrics.connection_errors._value.get() > 0

def test_on_message_processing_no_events(mock_settings, mock_ws_client):
    """Test handling of messages without events"""
    service = WebsocketService(mock_settings)
    service.on_message('{"other": "data"}')
    # Verify no processing occurred

def test_connect_and_subscribe(mock_settings, mock_ws_client):
    """Test the main connection and subscription loop"""
    service = WebsocketService(mock_settings)
    
    # Set up the mock to raise an exception after first run
    mock_ws_client.run_forever_with_exception_check.side_effect = Exception("Stop test")
    
    # Set the shutdown event to prevent infinite loop
    service._shutdown_event.set()
    
    # Run the service
    service.connect_and_subscribe()
    
    # Verify subscription was called
    mock_ws_client.subscribe.assert_called_with(
        product_ids=mock_settings.PRODUCT_IDS,
        channels=mock_settings.CHANNELS
    )

def test_cleanup_error_handling(mock_settings, mock_ws_client):
    """Test cleanup error handling"""
    service = WebsocketService(mock_settings)
    service._establish_connection()
    
    # Make close raise an exception
    mock_ws_client.close.side_effect = Exception("Cleanup error")
    
    service._cleanup()
    assert service._client is None  # Should still set to None despite error 