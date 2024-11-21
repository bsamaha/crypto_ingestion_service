# Build stage
FROM python:3.12-slim as builder

WORKDIR /app

# Copy only requirements first to leverage Docker cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ app/

# Runtime stage
FROM python:3.12-slim

WORKDIR /app

# Copy only necessary files from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages/ /usr/local/lib/python3.12/site-packages/
COPY --from=builder /app /app

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Set environment variables with defaults
ENV METRICS_PORT=8000 \
    LOG_LEVEL=INFO \
    ENABLE_HEARTBEAT=true \
    ENABLE_DEBUG_METRICS=false \
    KAFKA_ENABLED=true \
    KAFKA_TOPIC=coinbase.candles \
    KAFKA_BOOTSTRAP_SERVERS=trading-cluster-kafka-bootstrap.kafka:9092

EXPOSE 8000

CMD ["python", "-m", "app.main"] 