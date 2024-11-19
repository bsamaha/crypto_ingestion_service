# Coinbase WebSocket Ingestion Service

A high-performance WebSocket service for ingesting real-time cryptocurrency data from Coinbase's Advanced Trade API.

[![Coverage](docs/coverage_badge.svg)](docs/coverage_html/index.html)

## Overview

This service connects to Coinbase's WebSocket feed to ingest real-time candle data for specified cryptocurrency pairs. It features automatic reconnection, structured logging, comprehensive metrics, and health monitoring.

## Features

- Real-time WebSocket data ingestion with automatic reconnection
- Prometheus metrics for monitoring and alerting
- Health check endpoints for service status
- Structured JSON logging to stdout
- Docker containerization for easy deployment
- Comprehensive test coverage with detailed reports
- Graceful shutdown handling
- Windows and Unix platform support

## Prerequisites

- Python 3.12+
- Docker
- Coinbase Advanced Trade API credentials

## Quick Start

1. Clone the repository:
```bash
    git clone https://github.com/yourusername/coinbase_ingestion_service.git
    cd coinbase_ingestion_service
```

2. Set up environment variables:
```bash
    cp .env.example .env
    # Edit .env with your Coinbase API credentials
```

3. Run with Docker:
```bash
    ./utils/docker_build_and_run.sh
```

## Development

### Local Setup
```bash
    # Create virtual environment
    python -m venv .venv
    source .venv/bin/activate  # or `.venv\Scripts\activate` on Windows

    # Install dependencies
    pip install -r requirements.txt
```

### Running Tests
```bash
    ./utils/run_tests.sh
```

Test reports are generated in the `docs` directory:
- Coverage HTML report: `docs/coverage_html/index.html`
- Coverage XML report: `docs/coverage.xml`
- Coverage badge: `docs/coverage_badge.svg`

### Code Examples

#### WebSocket Service
The core WebSocket service handles connections and message processing:
```python
    from app.services.websocket_service import WebsocketService

    service = WebsocketService(settings)
    service.connect_and_subscribe()
```

#### Metrics Collection
Prometheus metrics are collected automatically:
```python
    from app.utils.metrics import metrics

    # Record a message
    metrics.record_message(
        symbol="BTC-USD",
        processing_time=0.001
    )

    # Get current values
    values = metrics.get_current_values()
```

## Configuration

Configuration is handled through environment variables or `.env` file:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `COINBASE_API_KEY` | Coinbase API Key | - | Yes |
| `COINBASE_API_SECRET` | Coinbase API Secret | - | Yes |
| `PRODUCT_IDS` | Trading pairs to monitor | `["BTC-USD", "ETH-USD"]` | No |
| `CHANNELS` | WebSocket channels | `["candles"]` | No |
| `WS_TIMEOUT` | WebSocket timeout (seconds) | 30 | No |
| `METRICS_PORT` | Metrics/health port | 8000 | No |
| `LOG_LEVEL` | Logging level | "INFO" | No |

## API Endpoints

### Health Check
```http
    GET /health

    Returns:
    - 200 OK: Service is healthy
    - 503 Service Unavailable: Service is unhealthy

    Health is determined by:
    - Message received in last minute
    - Within 5-minute startup grace period
```

### Metrics
```http
    GET /metrics

    Returns Prometheus-formatted metrics including:
    - websocket_messages_processed
    - websocket_messages_by_symbol{symbol="X"}
    - websocket_connection_errors
    - websocket_last_message_timestamp_seconds
    - message_processing_seconds (histogram)
```

## Project Structure
```
    .
    ├── app/
    │   ├── services/          # Core services
    │   ├── utils/            # Utility modules
    │   └── tests/            # Test suite
    ├── docs/                 # Documentation and reports
    ├── utils/               # Utility scripts
    └── README.md
```

## Best Practices

- All logs go to stdout (no file logging)
- Metrics follow Prometheus naming conventions
- Tests must maintain >80% coverage
- Documentation kept up-to-date with code
- Clean shutdown handling

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and ensure coverage
5. Submit a pull request

## License

[Your License Here]

## Support

For issues and feature requests, please use the GitHub issue tracker.