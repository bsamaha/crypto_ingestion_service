import logging
import json
from datetime import datetime
import structlog
from typing import Any, Dict
import sys

def setup_logging(log_level: str = "INFO"):
    # Convert string level to logging constant
    numeric_level = getattr(logging, log_level.upper())
    
    # Configure root logger first
    logging.getLogger().setLevel(numeric_level)
    
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.stdlib.add_log_level,
            structlog.processors.JSONRenderer()
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
    )
    
    # Configure logging to stdout only, no file
    logging.basicConfig(
        format="%(message)s",
        level=numeric_level,
        handlers=[
            logging.StreamHandler(sys.stdout)
        ],
        force=True
    )

def log_candle_json(candle: Dict[str, Any], logger: Any):
    """Log candle data in a structured format"""
    try:
        timestamp = datetime.fromtimestamp(int(candle['start'])).isoformat()
        
        message = {
            "event_time": timestamp,
            "symbol": candle['product_id'],
            "open_price": candle['open'],
            "high_price": candle['high'],
            "low_price": candle['low'],
            "close_price": candle['close'],
            "volume": candle['volume'],
            "start_time": int(candle['start'])
        }
        
        logger.info(json.dumps(message))
        
    except Exception as e:
        logger.error(f"Error formatting candle data: {str(e)}", exc_info=True) 