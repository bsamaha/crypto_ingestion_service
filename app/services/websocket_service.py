import json
import time
from typing import Optional
from backoff import on_exception, expo
import logging
from coinbase.websocket import WSClient, WSClientConnectionClosedException
from app.utils.logging_utils import log_candle_json
from app.config import Settings
from app.utils.metrics import metrics
import asyncio
from app.utils.kafka_producer import KafkaMessageProducer
from datetime import datetime

class WebsocketService:
    def __init__(self, config: Settings):
        self.config = config
        self._client: Optional[WSClient] = None
        self._should_run = True
        self.logger = logging.getLogger(__name__)
        self._shutdown_event = asyncio.Event()
        self.kafka_producer = KafkaMessageProducer(
            bootstrap_servers=config.KAFKA_BOOTSTRAP_SERVERS,
            enabled=config.KAFKA_ENABLED
        )
        self._kafka_connected = False
    
    async def start(self):
        """Initialize and start the service"""
        if self.config.KAFKA_ENABLED:
            try:
                await self.kafka_producer.connect()
                self._kafka_connected = True
            except Exception as e:
                self.logger.error(f"Failed to start Kafka producer: {str(e)}")
                raise
        else:
            self.logger.info("Kafka integration disabled, skipping connection")

    async def stop(self):
        """Graceful shutdown method"""
        self.logger.info("Initiating graceful shutdown...")
        self._should_run = False
        self._shutdown_event.set()
        
        if self._kafka_connected:
            await self.kafka_producer.disconnect()
        
        if self._client:
            try:
                if hasattr(self._client, 'close') and asyncio.iscoroutinefunction(self._client.close):
                    await self._client.close()
                else:
                    self._client.close()
            except Exception as e:
                self.logger.error(f"Error during shutdown: {str(e)}")
            finally:
                self._client = None
        self.logger.info("Shutdown complete")

    @on_exception(expo, WSClientConnectionClosedException, max_tries=5)
    def _establish_connection(self):
        """Establish websocket connection with exponential backoff"""
        self._client = WSClient(
            api_key=self.config.COINBASE_API_KEY,
            api_secret=self.config.COINBASE_API_SECRET,
            on_message=self.on_message,
            on_open=self.on_open,
            timeout=self.config.WS_TIMEOUT,
            max_size=self.config.WS_MAX_SIZE
        )
        self._client.open()
        return self._client

    def on_message(self, ws_object):
        try:
            start_time = time.time()
            message = json.loads(ws_object) if isinstance(ws_object, str) else ws_object
                
            if 'events' in message:
                for event in message['events']:
                    if 'type' in event:
                        if event['type'] in ['snapshot', 'update']:
                            for candle in event.get('candles', []):
                                log_candle_json(candle, self.logger)
                                
                                if self.config.KAFKA_ENABLED:
                                    kafka_message = {
                                        "event_time": datetime.fromtimestamp(int(candle['start'])).isoformat(),
                                        "symbol": candle['product_id'],
                                        "open_price": candle['open'],
                                        "high_price": candle['high'],
                                        "low_price": candle['low'],
                                        "close_price": candle['close'],
                                        "volume": candle['volume'],
                                        "start_time": int(candle['start'])
                                    }
                                    
                                    asyncio.create_task(self.kafka_producer.send_message(self.config.KAFKA_TOPIC, kafka_message))
                                
                                metrics.record_message(
                                    symbol=candle['product_id'],
                                    processing_time=time.time() - start_time
                                )
                    
        except json.JSONDecodeError as e:
            metrics.connection_errors.inc()
            self.logger.error(f"Failed to parse message as JSON: {str(e)}", exc_info=True)
        except Exception as e:
            metrics.connection_errors.inc()
            self.logger.error(f"Error processing message: {str(e)}", exc_info=True)

    def on_open(self):
        self.logger.info("Connected to Coinbase Pro")

    def connect_and_subscribe(self):
        """Main connection loop with shutdown handling"""
        while self._should_run:
            try:
                client = self._establish_connection()
                client.subscribe(
                    product_ids=self.config.PRODUCT_IDS,
                    channels=self.config.CHANNELS
                )
                
                self.logger.info("Starting WebSocket connection...")
                
                # Run until shutdown event is set
                while self._should_run and not self._shutdown_event.is_set():
                    client.run_forever_with_exception_check()
                    time.sleep(0.1)  # Small delay to prevent CPU spinning
                
                if self._shutdown_event.is_set():
                    self.logger.info("Shutdown event received, stopping connection...")
                    break
                    
            except Exception as e:
                self.logger.error(f"Unexpected error: {str(e)}", exc_info=True)
                if not self._should_run:
                    break
                time.sleep(self.config.RECONNECT_DELAY)
            finally:
                self._cleanup()
        
        self.logger.info("WebSocket service stopped")

    def _cleanup(self):
        """Clean up resources"""
        if self._client:
            try:
                self._client.close()
            except Exception as e:
                self.logger.error(f"Error during cleanup: {str(e)}")
            finally:
                self._client = None