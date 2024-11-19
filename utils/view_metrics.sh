#!/bin/bash
set -e  # Exit on any error

PORT=8000
METRICS_ENDPOINT="http://localhost:$PORT/metrics"

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
                    echo "📅 Last Message: $human_time"
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

    echo ""
    echo "🔍 Raw Metric Values:"
    curl -s "$METRICS_ENDPOINT" | grep -v "^#" | sort
}

echo "🔍 Fetching metrics from $METRICS_ENDPOINT..."
echo "----------------------------------------"

if ! curl -s "$METRICS_ENDPOINT" | format_metrics; then
    echo "❌ Failed to fetch metrics!"
    exit 1
fi

echo "----------------------------------------"

# Show service health status
HEALTH_STATUS=$(curl -s "http://localhost:$PORT/health")
echo "💓 Service Health: $HEALTH_STATUS"

# Show container stats
echo ""
echo "📈 Container Stats:"
docker stats coinbase-ws --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 