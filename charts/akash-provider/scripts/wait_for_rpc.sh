#!/bin/bash
# Filename: wait_for_rpc.sh
#
# Waits until the RPC node ($AKASH_NODE) answers and is synced, then checks that its latest block
# is not far from the local clock. Gives up after WAIT_FOR_RPC_TIMEOUT seconds (default 600).

source /scripts/lib.sh

timeout_s=${WAIT_FOR_RPC_TIMEOUT:-600}
deadline=$(( $(date +%s) + timeout_s ))

# One request per try: the answer that says "synced" also carries the latest block time used below,
# so no second request can fail after the wait succeeded.
until status=$(curl -s --max-time 10 "$AKASH_NODE/status") &&
  [[ "$(jq -r '.result.sync_info.catching_up' <<<"$status" 2>/dev/null)" == "false" ]]; do
  if (( $(date +%s) >= deadline )); then
    fail "RPC node not ready after ${timeout_s}s" "$AKASH_NODE does not answer or is still catching up" \
      "check .Values.node and that the node is reachable and synced"
  fi
  log_info "waiting for RPC node $AKASH_NODE (not reachable or still catching up)"
  sleep 3
done

block_time=$(jq -r '.result.sync_info.latest_block_time' <<<"$status")
if ! block_s=$(date +%s --date "$block_time" 2>/dev/null); then
  fail "RPC node returned no valid block time" "latest_block_time=\"$block_time\" from $AKASH_NODE/status" \
    "check .Values.node points to an Akash RPC node"
fi
diff_s=$(( $(date +%s) - block_s ))
if (( diff_s > 30 || diff_s < -30 )); then
  fail "RPC node and local clock differ by ${diff_s}s" "latest block at $block_time on $AKASH_NODE" \
    "synchronize the system time and/or check the RPC node"
fi
log_info "RPC node ready: $AKASH_NODE (latest block ${diff_s}s ago)"
