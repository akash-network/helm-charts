#!/bin/bash

# Ensure the script fails if any part of a pipeline fails
set -o pipefail

# Check provider certificate expiration
if ! openssl x509 -in /config/provider.pem -checkend 3600 -noout > /dev/null; then
  echo "certificate will expire in 1h, restarting"
  exit 1
fi

# Provider API /status check
if ! timeout 30s curl -o /dev/null -fsk https://127.0.0.1:8443/status; then
  echo "api /status check failed"
  exit 1
fi

# Provider gRPC check
if ! timeout 30s curl -k -v --http2-prior-knowledge https://127.0.0.1:8444 2>&1 | grep -qi 'application/grpc'; then
  echo "gRPC check failed"
  exit 1
fi

# RPC node sync check
current_time=$(date -u +%s)
latest_block_time_str=$(curl -s $AKASH_NODE/status | jq -r '.result.sync_info.latest_block_time')
latest_block_time=$(date -u -d "$latest_block_time_str" +%s)

# Allow for a 60 seconds drift
let "time_diff = current_time - latest_block_time"
if [ "$time_diff" -gt 60 ] || [ "$time_diff" -lt -60 ]; then
  echo "RPC node sync check failed"
  exit 1
fi

echo "All checks passed"
exit 0
