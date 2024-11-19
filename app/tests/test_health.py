import pytest
from fastapi.testclient import TestClient
from app.services.health import app
from app.utils.metrics import metrics
from datetime import datetime, timedelta

@pytest.fixture
def client():
    return TestClient(app)

def test_health_check_healthy(client):
    """Test health check endpoint when service is healthy"""
    # Set last message timestamp to recent
    metrics.last_message_timestamp.set(datetime.now().timestamp())
    
    response = client.get("/health")
    assert response.status_code == 200
    assert response.text == "healthy"

def test_health_check_unhealthy(client):
    """Test health check endpoint when service is unhealthy"""
    # Set last message timestamp to old (beyond grace period)
    old_time = (datetime.now() - timedelta(minutes=6)).timestamp()
    metrics.last_message_timestamp.set(old_time)
    
    response = client.get("/health")
    assert response.status_code == 503
    assert response.text == "unhealthy"

def test_metrics_endpoint(client):
    """Test metrics endpoint returns prometheus metrics"""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "websocket_messages_processed_total" in response.text
    assert "last_message_timestamp" in response.text 