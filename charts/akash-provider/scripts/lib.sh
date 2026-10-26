#!/bin/bash
# Filename: lib.sh
#
# Shared helpers for the chart scripts; sourced, not executed.
# Logs go to stderr, data (addresses, JSON) to stdout, so a function's output can be captured
# with $(...) while its log lines still reach the pod log.

set -euo pipefail
shopt -s inherit_errexit

log_step() { echo "==> [$1]" >&2; }
log_info() { echo "INFO  $*" >&2; }
log_warn() { echo "WARN  $*" >&2; }

# fail <what went wrong> <what was found> <what to do>: prints an ERROR block and exits 1.
fail() {
  echo "ERROR $1" >&2
  echo "ERROR   found: $2" >&2
  echo "ERROR   to fix: $3" >&2
  exit 1
}

# run <cmd...>: prints the command, then runs it.
run() {
  echo "+ $*" >&2
  "$@"
}

# is_address <text>: true if the text has the form of an account address: "akash1" followed by 38
# bech32 characters. The checksum is not verified.
is_address() {
  [[ "$1" =~ ^akash1[02-9ac-hj-np-z]{38}$ ]]
}

# chain_query <cmd...>: runs a read-only chain query and prints its JSON result.
# Returns 0 when found and 3 when the chain answers "not found" (gRPC NotFound).
# Any other error (RPC down, timeout, ...) is retried, then stops the script: a chain error
# is never treated as "not found".
chain_query() {
  local out err try
  err=$(mktemp)
  for try in 1 2 3; do
    if out=$(timeout 30 "$@" 2>"$err"); then
      rm -f "$err"
      echo "$out"
      return 0
    fi
    if grep -q 'code = NotFound' "$err"; then
      rm -f "$err"
      return 3
    fi
    log_warn "chain query failed (try $try/3): $(tail -1 "$err" | cut -c1-200)"
    sleep 3
  done
  fail "cannot read from the chain" "$(tail -1 "$err" | cut -c1-200)" "check the RPC node $AKASH_NODE"
}

# send_tx <cmd...>: broadcasts a transaction (block mode) and logs its height and hash.
# Stops the script if the CLI fails or the chain rejects the transaction.
send_tx() {
  local out code
  echo "+ $*" >&2
  if ! out=$("$@" -o json 2>&1); then
    fail "transaction failed" "$(echo "$out" | tail -1 | cut -c1-300)" "see the error above; nothing was changed on chain"
  fi
  code=$(jq -r '.code // 0' <<<"$out" 2>/dev/null || echo "?")
  if [[ "$code" != "0" ]]; then
    fail "transaction rejected by the chain" "code $code: $(jq -r '.raw_log // empty' <<<"$out" | cut -c1-300)" "see the error above"
  fi
  log_info "transaction included: height $(jq -r '.height' <<<"$out"), hash $(jq -r '.txhash' <<<"$out")"
}
