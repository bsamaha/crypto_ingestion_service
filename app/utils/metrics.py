from dataclasses import dataclass, field
from datetime import datetime
import threading
from typing import Dict
import prometheus_client as prom
import logging
from prometheus_client import REGISTRY

@dataclass
class Metrics:
    def __init__(self, registry=REGISTRY):
        """Initialize metrics with consistent naming"""
        self.registry = registry
        
        self.messages_processed = prom.Counter(
            'websocket_messages_processed',
            'Total number of websocket messages processed',
            registry=self.registry
        )
        
        self.connection_errors = prom.Counter(
            'websocket_connection_errors',
            'Total number of websocket connection errors',
            registry=self.registry
        )
        
        self.message_processing_time = prom.Histogram(
            'message_processing_seconds',
            'Time spent processing messages',
            buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25),
            registry=self.registry
        )
        
        self.last_message_timestamp = prom.Gauge(
            'websocket_last_message_timestamp_seconds',
            'Unix timestamp of last received message',
            registry=self.registry
        )
        
        self.messages_by_symbol = prom.Counter(
            'websocket_messages_by_symbol', 
            'Total messages received by symbol',
            ['symbol'],
            registry=self.registry
        )

    def record_message(self, symbol: str, processing_time: float):
        """Record a processed message with its symbol and processing time"""
        logger = logging.getLogger(__name__)
        try:
            logger.debug(f"Recording message for symbol {symbol}")
            self.messages_processed.inc()
            self.messages_by_symbol.labels(symbol=symbol).inc()
            self.message_processing_time.observe(processing_time)
            current_time = datetime.now().timestamp()
            self.last_message_timestamp.set(current_time)
            logger.debug(f"Successfully recorded message. Total count: {self.messages_processed._value.get()}")
        except Exception as e:
            logger.error(f"Error recording metrics: {str(e)}", exc_info=True)

    def get_current_values(self) -> dict:
        """Get current values of all metrics for debugging"""
        return {
            'messages_processed': self.messages_processed._value.get(),
            'connection_errors': self.connection_errors._value.get(),
            'last_message_timestamp': self.last_message_timestamp._value.get(),
            'messages_by_symbol': {
                symbol: self.messages_by_symbol.labels(symbol=symbol)._value.get()
                for symbol in ['BTC-USD', 'ETH-USD']
            }
        }

# Create a single instance for the application
metrics = Metrics() 