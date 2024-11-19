import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.main import main, run_health_server
import signal
import asyncio
import sys
import platform

@pytest.mark.asyncio
async def test_run_health_server():
    """Test health server startup"""
    mock_server = AsyncMock()
    mock_config = MagicMock()
    
    with patch('uvicorn.Server', return_value=mock_server) as mock_server_class:
        with patch('uvicorn.Config', return_value=mock_config) as mock_config_class:
            server_task = asyncio.create_task(run_health_server(8000))
            await asyncio.sleep(0.1)
            server_task.cancel()
            
            try:
                await server_task
            except asyncio.CancelledError:
                pass
            
            mock_config_class.assert_called_once()
            assert mock_config_class.call_args[1]['host'] == "0.0.0.0"
            assert mock_config_class.call_args[1]['port'] == 8000
            assert mock_config_class.call_args[1]['log_level'] == "info"
            mock_server.serve.assert_called_once()

@pytest.mark.asyncio
@pytest.mark.skipif(
    platform.system() == "Windows",
    reason="Signal handlers not supported on Windows"
)
async def test_main_shutdown_handling():
    """Test main function handles shutdown correctly"""
    mock_ws_service = MagicMock()
    mock_settings = MagicMock()
    mock_health_task = AsyncMock()
    
    mock_ws_service.stop = AsyncMock()
    mock_ws_service.connect_and_subscribe = MagicMock(side_effect=KeyboardInterrupt)
    
    with patch('app.main.get_settings', return_value=mock_settings), \
         patch('app.main.WebsocketService', return_value=mock_ws_service), \
         patch('app.main.setup_logging') as mock_setup_logging, \
         patch('asyncio.create_task', return_value=mock_health_task):
        
        try:
            await main()
        except KeyboardInterrupt:
            pass
        
        mock_setup_logging.assert_called_once_with(mock_settings.LOG_LEVEL)
        mock_ws_service.stop.assert_awaited_once()
        mock_health_task.cancel.assert_called_once()

@pytest.fixture(autouse=True)
async def cleanup_event_loop():
    """Cleanup any pending tasks after each test"""
    yield
    # Clean up any pending tasks
    tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    for task in tasks:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass