from fastapi import FastAPI, Response
from prometheus_client import generate_latest
from datetime import datetime, timedelta
from app.utils.metrics import metrics

app = FastAPI()

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Get last message timestamp from metrics
        last_msg_time = datetime.fromtimestamp(metrics.last_message_timestamp._value.get())
        startup_grace_period = datetime.now() - timedelta(minutes=5)
        
        # Service is healthy if:
        # 1. We received a message in the last minute OR
        # 2. We're within the startup grace period
        is_healthy = (datetime.now() - last_msg_time < timedelta(minutes=1)) or \
                    (startup_grace_period < last_msg_time)
        
        return Response(
            status_code=200 if is_healthy else 503,
            content="healthy" if is_healthy else "unhealthy"
        )
    except Exception:
        # During startup, when no messages have been received yet
        return Response(status_code=200, content="healthy")

@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    # Generate Prometheus format metrics
    return Response(
        generate_latest(),  # Convert all metrics to Prometheus format
        media_type="text/plain"
    )