import pytest
from app.utils.metrics import Metrics
from prometheus_client import REGISTRY, CollectorRegistry

@pytest.fixture
def clean_registry():
    """Provide a clean registry for each test"""
    registry = CollectorRegistry()
    # Store the default registry
    default_registry = REGISTRY
    # Set our clean registry as the default
    from prometheus_client import core
    core.REGISTRY = registry
    yield registry
    # Restore the default registry
    core.REGISTRY = default_registry

def test_metrics_initialization(clean_registry):
    """Test metrics are properly initialized"""
    test_metrics = Metrics(registry=clean_registry)
    
    # Verify metric names
    assert test_metrics.messages_processed._name == "websocket_messages_processed"
    assert test_metrics.connection_errors._name == "websocket_connection_errors"
    assert test_metrics.message_processing_time._name == "message_processing_seconds"
    assert test_metrics.last_message_timestamp._name == "websocket_last_message_timestamp_seconds"
    assert test_metrics.messages_by_symbol._name == "websocket_messages_by_symbol"

def test_metrics_registration(clean_registry):
    """Test metrics are registered with Prometheus"""
    test_metrics = Metrics(registry=clean_registry)
    
    # Get all registered metric names
    collectors = list(clean_registry._collector_to_names.values())
    registered_names = [name for names in collectors for name in names]
    
    # Verify our metrics are registered
    assert any("websocket_messages_processed" in name for name in registered_names)
    assert any("websocket_connection_errors" in name for name in registered_names)
    assert any("message_processing_seconds" in name for name in registered_names)
    assert any("websocket_last_message_timestamp_seconds" in name for name in registered_names)

def test_metrics_updates(clean_registry):
    """Test metrics can be updated"""
    test_metrics = Metrics(registry=clean_registry)
    
    # Test counter increment
    test_metrics.messages_processed.inc()
    assert test_metrics.messages_processed._value.get() > 0
    
    # Test error counter
    test_metrics.connection_errors.inc()
    assert test_metrics.connection_errors._value.get() > 0
    
    # Test timestamp update
    timestamp = 1637001600
    test_metrics.last_message_timestamp.set(timestamp)
    assert test_metrics.last_message_timestamp._value.get() == timestamp

    # Test symbol counter
    test_metrics.messages_by_symbol.labels(symbol="BTC-USD").inc()
    assert test_metrics.messages_by_symbol.labels(symbol="BTC-USD")._value.get() > 0