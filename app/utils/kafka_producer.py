from aiokafka import AIOKafkaProducer
import json
import logging
from typing import Any, Dict, Optional
import asyncio
from datetime import datetime

logger = logging.getLogger(__name__)

class KafkaMessageProducer:
    def __init__(self, bootstrap_servers: str = "trading-cluster-kafka-bootstrap.kafka:9092", enabled: bool = True):
        self.bootstrap_servers = bootstrap_servers
        self.enabled = enabled
        self.producer: Optional[AIOKafkaProducer] = None
        self._connected = False
        self.logger = logging.getLogger(__name__)

    async def connect(self) -> None:
        """Connect to Kafka broker"""
        try:
            self.producer = AIOKafkaProducer(
                bootstrap_servers=self.bootstrap_servers,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                retry_backoff_ms=500,
                max_batch_size=16384
            )
            await self.producer.start()
            self._connected = True
            self.logger.info("Connected to Kafka broker")
        except Exception as e:
            self.logger.error(f"Failed to connect to Kafka: {str(e)}", exc_info=True)
            raise

    async def disconnect(self) -> None:
        """Disconnect from Kafka broker"""
        if self.producer is not None:
            try:
                await self.producer.stop()
                self._connected = False
                self.logger.info("Disconnected from Kafka broker")
            except Exception as e:
                self.logger.error(f"Error disconnecting from Kafka: {str(e)}", exc_info=True)

    async def send_message(self, topic: str, message: Dict[str, Any]) -> None:
        """Send message to Kafka topic"""
        if not self.enabled:
            self.logger.debug("Kafka publishing disabled, skipping message")
            return
        
        if not self._connected or self.producer is None:
            raise RuntimeError("Not connected to Kafka broker")
        
        try:
            # Add timestamp if not present
            if 'timestamp' not in message:
                message['timestamp'] = datetime.utcnow().isoformat()
            
            await self.producer.send_and_wait(topic, message)
            self.logger.debug(f"Message sent to topic {topic}")
        except Exception as e:
            self.logger.error(f"Failed to send message to Kafka: {str(e)}", exc_info=True)
            raise 