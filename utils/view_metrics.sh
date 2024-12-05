#!/bin/bash
set -e  # Exit on any error

# Default values
NAMESPACE="trading"
PORT=8000
POD_LABEL="app=coinbase-ws"  # Actual label from kubectl describe
LOCAL_PORT=8001  # Local port to forward to

# Function to get pod name
get_pod_name() {
    kubectl get pods -n "$NAMESPACE" -l "$POD_LABEL" -o jsonpath='{.items[0].metadata.name}'
}

# Function to cleanup port-forward
cleanup() {
    echo "Cleaning up port-forward..."
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT

# Function to format timestamp to human readable date
format_timestamp() {
    local timestamp=$1
    if [[ $timestamp =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        date -d "@${timestamp%.*}" "+%Y-%m-%d %H:%M:%S"
    else
        echo "Invalid timestamp"
    fi
}

# Function to format metrics output
format_metrics() {
    local messages_total=0
    local errors_total=0
    declare -A symbol_counts

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        if [[ $line =~ ([a-zA-Z_]+)({.*})?[[:space:]]+(.*) ]]; then
            metric_name="${BASH_REMATCH[1]}"
            metric_labels="${BASH_REMATCH[2]}"
            metric_value="${BASH_REMATCH[3]}"
            
            case $metric_name in
                "websocket_messages_processed_total")
                    messages_total=$metric_value
                    ;;
                "websocket_connection_errors_total")
                    errors_total=$metric_value
                    ;;
                "websocket_last_message_timestamp_seconds")
                    human_time=$(format_timestamp "$metric_value")
                    echo " Last Message: $human_time"
                    ;;
                "websocket_messages_by_symbol_total")
                    if [[ $metric_labels =~ symbol=\"([^\"]+)\" ]]; then
                        symbol="${BASH_REMATCH[1]}"
                        symbol_counts[$symbol]=$metric_value
                    fi
                    ;;
                "message_processing_seconds"*)
                    if [[ $line =~ \{.*le=\"(.+)\"\}.* ]]; then
                        bucket="${BASH_REMATCH[1]}"
                        echo "⏱️  Processing Time (<${bucket}s): $metric_value"
                    fi
                    ;;
            esac
        fi
    done

    echo "📨 Total Messages: $messages_total"
    echo "❌ Total Errors: $errors_total"
    
    if [ ${#symbol_counts[@]} -gt 0 ]; then
        echo "📊 Messages by Symbol:"
        for symbol in "${!symbol_counts[@]}"; do
            echo "   $symbol: ${symbol_counts[$symbol]}"
        done
    fi
}

POD_NAME=$(get_pod_name)
if [ -z "$POD_NAME" ]; then
    echo "❌ No pod found with label $POD_LABEL in namespace $NAMESPACE"
    exit 1
fi

echo "🔍 Setting up port-forward to pod $POD_NAME..."
kubectl port-forward -n "$NAMESPACE" "$POD_NAME" "$LOCAL_PORT:$PORT" &
PORT_FORWARD_PID=$!

# Wait for port-forward to be ready
sleep 2

echo "----------------------------------------"

# Show raw metrics first
echo "🔍 Raw Metrics:"
curl -s "http://localhost:$LOCAL_PORT/metrics"
echo ""
echo "----------------------------------------"
echo "📊 Formatted Metrics:"

# Get metrics using local port-forward
if ! curl -s "http://localhost:$LOCAL_PORT/metrics" | format_metrics; then
    echo "❌ Failed to fetch metrics!"
    exit 1
fi

echo "----------------------------------------"

# Show pod health status
HEALTH_STATUS=$(curl -s "http://localhost:$LOCAL_PORT/health")
echo "💓 Pod Health: $HEALTH_STATUS"

# Show pod resource usage
echo ""
echo "📈 Pod Stats:"
kubectl top pod "$POD_NAME" -n "$NAMESPACE"