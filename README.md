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

# Private Registry Setup and Workflow

## Registry Information
- Registry Address: `{registry_ip_address}{registry_port}`
- SSL: Self-signed certificate
- Access: Available within local network

## Development Workflow

### Initial Setup

1. **Configure Docker Desktop**
   ```powershell
   # Verify registry connection
   curl -k https://{registry_ip_address}{registry_port}/v2/_catalog
   ```

2. **Build Images for Local Development**
   ```bash
   # Format: {registry_ip_address}{registry_port}/{project-name}:{tag}
   docker build -t {registry_ip_address}{registry_port}/myproject:dev .
   docker push {registry_ip_address}{registry_port}/myproject:dev
   ```

### Daily Development Workflow

1. **Building Images**
   ```bash
   # Development builds
   docker build -t {registry_ip_address}{registry_port}/myproject:dev .
   
   # Feature branches
   docker build -t {registry_ip_address}{registry_port}/myproject:feature-name .
   
   # Release versions
   docker build -t {registry_ip_address}{registry_port}/myproject:v1.0.0 .
   ```

2. **Testing Locally**
   ```bash
   # Run locally before pushing
   docker run -d {registry_ip_address}{registry_port}/myproject:dev
   
   # Run integration tests
   docker-compose -f docker-compose.test.yml up
   ```

3. **Pushing to Registry**
   ```bash
   # Push development version
   docker push {registry_ip_address}{registry_port}/myproject:dev
   
   # Push release version
   docker push {registry_ip_address}{registry_port}/myproject:v1.0.0
   ```

### Kubernetes Deployment

1. **Update Kubernetes Manifests**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: myapp
   spec:
     template:
       spec:
         containers:
         - name: myapp
           image: {registry_ip_address}{registry_port}/myproject:dev  # Use registry address
   ```

2. **Apply Updates**
   ```bash
   kubectl apply -f k8s/deployment.yaml
   ```

### Best Practices

1. **Image Tagging Convention**
   - `dev`: Latest development build
   - `feature-*`: Feature branch builds
   - `v*.*.*`: Release versions
   - `latest`: Stable production build

2. **Registry Maintenance**
   - Regularly clean up old development tags
   - Keep release versions tagged properly
   - Document breaking changes in image versions

3. **Local Development**
   - Always test builds locally before pushing
   - Use docker-compose for multi-container testing
   - Tag images appropriately for different environments

### Troubleshooting

1. **Registry Connection Issues**
   ```bash
   # Test registry connection
   curl -k https://{registry_ip_address}{registry_port}/v2/_catalog
   
   # Check registry contents
   curl -k https://{registry_ip_address}{registry_port}/v2/{repository}/tags/list
   ```

2. **Common Issues**
   - Certificate errors: Verify registry certificate is properly installed
   - Push failures: Check network connectivity and Docker daemon settings
   - Pull failures in k8s: Verify node configuration and registry access

### CI/CD Integration

1. **Local CI Runner Setup**
   ```yaml
   # .gitlab-ci.yml or GitHub Actions example
   build:
     script:
       - docker build -t {registry_ip_address}{registry_port}/myproject:${CI_COMMIT_SHA} .
       - docker push {registry_ip_address}{registry_port}/myproject:${CI_COMMIT_SHA}
   ```

2. **Deployment Automation**
   ```bash
   # Example deployment script
   TAG=$(git rev-parse --short HEAD)
   docker build -t {registry_ip_address}{registry_port}/myproject:${TAG} .
   docker push {registry_ip_address}{registry_port}/myproject:${TAG}
   sed -i "s|image:.*|image: {registry_ip_address}{registry_port}/myproject:${TAG}|" k8s/deployment.yaml
   kubectl apply -f k8s/deployment.yaml
   ```

### Environment Setup Scripts

1. **Windows PowerShell**
   ```powershell
   # Set environment variables
   $env:REGISTRY_HOST="{registry_ip_address}{registry_port}"
   $env:PROJECT_NAME="myproject"
   
   # Build and push
   docker build -t ${env:REGISTRY_HOST}/${env:PROJECT_NAME}:dev .
   docker push ${env:REGISTRY_HOST}/${env:PROJECT_NAME}:dev
   ```

2. **Linux/WSL2**
   ```bash
   # Set environment variables
   export REGISTRY_HOST="{registry_ip_address}{registry_port}"
   export PROJECT_NAME="myproject"
   
   # Build and push
   docker build -t ${REGISTRY_HOST}/${PROJECT_NAME}:dev .
   docker push ${REGISTRY_HOST}/${PROJECT_NAME}:dev
   ```

### Security Notes

- Registry uses self-signed certificates
- Access is restricted to local network
- No authentication required (internal use only)
- Keep sensitive data out of image builds

### Additional Resources

- [Docker Registry Documentation](https://docs.docker.com/registry/)
- [Kubernetes Private Registry Guide](https://kubernetes.io/docs/concepts/containers/images/#using-a-private-registry)
- Team-specific documentation (add links here)
## Support

For issues and feature requests, please use the GitHub issue tracker.