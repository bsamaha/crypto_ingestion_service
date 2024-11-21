import asyncio
import logging
import structlog
import uvicorn
from app.config import get_settings
from app.services.websocket_service import WebsocketService
from app.services.health import app as health_app
from app.utils.logging_utils import setup_logging
from app.utils.metrics import metrics
import signal
from datetime import datetime
import sys
import platform

logger = structlog.get_logger()

async def run_health_server(port: int):
    """Run the health check server"""
    config = uvicorn.Config(
        health_app,
        host="0.0.0.0",
        port=port,
        log_level="info"
    )
    server = uvicorn.Server(config)
    await server.serve()

def handle_exception(loop, context):
    message = context.get("exception", context["message"]) # type: ignore
    logger.error(f"Caught exception: {message}")
    asyncio.create_task(shutdown())

async def shutdown():
    logger.info("Shutting down...")
    tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    [task.cancel() for task in tasks]
    logger.info(f"Cancelling {len(tasks)} outstanding tasks")
    await asyncio.gather(*tasks, return_exceptions=True)
    logger.info("Shutdown complete")

async def main():
    loop = asyncio.get_event_loop()
    loop.set_exception_handler(handle_exception)
    
    settings = get_settings()
    setup_logging(settings.LOG_LEVEL)
    
    # Initialize metrics with current timestamp
    metrics.last_message_timestamp.set(datetime.now().timestamp())
    
    # Start health check server
    health_task = asyncio.create_task(run_health_server(settings.METRICS_PORT))
    
    ws_service = WebsocketService(settings)
    
    def signal_handler():
        logger.info("Signal received, initiating shutdown...")
        asyncio.create_task(ws_service.stop())
        asyncio.create_task(shutdown())
    
    # Only set up signal handlers on non-Windows platforms
    if platform.system() != 'Windows':
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, signal_handler)
    
    try:
        # Initialize Kafka producer
        await ws_service.start()
        
        # Start WebSocket connection
        await asyncio.get_event_loop().run_in_executor(None, ws_service.connect_and_subscribe)
    except (Exception, KeyboardInterrupt) as e:
        if isinstance(e, KeyboardInterrupt):
            logger.info("Keyboard interrupt received")
        else:
            logger.error("fatal_error", error=str(e), exc_info=True)
    finally:
        await ws_service.stop()
        health_task.cancel()
        try:
            await health_task
        except asyncio.CancelledError:
            pass

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt, shutting down...")
    finally:
        logger.info("Application shutdown complete")
