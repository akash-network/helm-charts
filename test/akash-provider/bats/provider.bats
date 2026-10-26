#!/usr/bin/env bats
# akash-provider chart scripts (init.sh, create_provider.sh, refresh_provider_cert.sh, run.sh)
# against a localnet chain in kind. Tests run in order and share one provider install:
# `make test` resets the chain and the provider first, test 01 installs it.
#
# Transactions are counted with the provider account's sequence number.

load helpers

teardown() {
  if [[ -z "${BATS_TEST_COMPLETED:-}" ]]; then dump_state; fi
}

expect_eq() {
  [[ "$1" == "$2" ]] || { echo "$3: got '$1', want '$2'" >&2; return 1; }
}

@test "01 fresh install: provider and certificate created with 2 transactions" {
  run make -s -C "$ROOT" provider
  [[ "$status" -eq 0 ]] || { echo "$output" | tail -30; false; }

  expect_eq "$(init_exit_code)" 0 "init exit code"
  expect_eq "$(seq_now)" 2 "transactions (create provider, publish cert)"

  run provider_json
  expect_eq "$(jq -r .host_uri <<<"$output")" "https://$DOMAIN:8443" "host_uri"
  expect_eq "$(jq -c '[.attributes[] | "\(.key)=\(.value)"]' <<<"$output")" '["region=localnet","host=akash"]' "attributes"
  expect_eq "$(jq -r .info.email <<<"$output")" "e2e@localnet.test" "email"

  expect_eq "$(valid_serials)" "$(local_serial)" "the only valid cert on chain is the local one"

  # one provider key on the volume, shared by akt and the daemon
  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$(addr)")" "keys on the volume"
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
  grep -q "init done: provider $(addr)" <<<"$output" || { echo "init log has no summary line" >&2; false; }
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c provider
  grep -q "starting: /usr/bin/provider-services run --from $(addr)" <<<"$output" || { echo "daemon not started with the address" >&2; false; }
}

@test "02 pod delete: init reruns, no transactions, same certificate" {
  local seq0 serial0
  seq0=$(seq_now); serial0=$(local_serial)

  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy

  expect_eq "$(seq_now)" "$seq0" "transactions"
  expect_eq "$(local_serial)" "$serial0" "local cert serial"
}

@test "03 main container restart: init does not rerun, no transactions" {
  local seq0 init0 restarts0 i
  seq0=$(seq_now); init0=$(init_started); restarts0=$(main_restarts)

  prov kill 1 || true
  for i in $(seq 1 60); do
    [[ "$(main_restarts)" -gt "$restarts0" ]] && break
    sleep 2
  done
  expect_eq "$(main_restarts)" "$((restarts0 + 1))" "main container restarts"
  wait_healthy

  expect_eq "$(init_started)" "$init0" "init container start time"
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "04 helm upgrade without changes: no rollout, no transactions" {
  local seq0 uid0
  seq0=$(seq_now); uid0=$(pod_uid)

  upgrade_provider
  sleep 5

  expect_eq "$(pod_uid)" "$uid0" "pod uid"
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "05 attribute change: rollout, provider updated with 1 transaction" {
  local seq0 uid0 values
  seq0=$(seq_now); uid0=$(pod_uid)
  values="$BATS_TEST_TMPDIR/attributes.yaml"
  cat >"$values" <<'EOF'
attributes:
- key: region
  value: localnet-2
- key: host
  value: akash
EOF

  upgrade_provider -f "$values"
  wait_new_pod "$uid0"
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy

  expect_eq "$(seq_now)" "$((seq0 + 1))" "transactions (update provider)"
  expect_eq "$(provider_json | jq -c '[.attributes[] | "\(.key)=\(.value)"]')" '["region=localnet-2","host=akash"]' "attributes on chain"
}

@test "06 certificate file missing: new certificate published with 1 transaction" {
  local seq0 serial0 serial1
  seq0=$(seq_now); serial0=$(local_serial)

  rm_node_cert
  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy

  expect_eq "$(seq_now)" "$((seq0 + 1))" "transactions (publish cert)"
  serial1=$(local_serial)
  [[ "$serial1" != "$serial0" ]] || { echo "certificate was not regenerated" >&2; false; }
  grep -qx "$serial1" <<<"$(valid_serials)" || { echo "new cert $serial1 not valid on chain" >&2; false; }
}

@test "07 certificate expiring within 7 days: replaced on restart, next restart sends nothing" {
  local seq0 seq1
  seq0=$(seq_now)

  # A 72h certificate, generated and published the way the chart scripts do it.
  prov provider-services tx cert generate server "$DOMAIN" --valid-duration 72h --overwrite >/dev/null
  prov provider-services tx cert publish server >/dev/null
  wait_seq "$((seq0 + 1))"
  ! local_cert_valid_for 604800 || { echo "test setup: cert is not short-lived" >&2; false; }

  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy

  expect_eq "$(seq_now)" "$((seq0 + 2))" "transactions (test publish + regenerated cert)"
  local_cert_valid_for 604800 || { echo "certificate still expires within 7 days" >&2; false; }
  grep -qx "$(local_serial)" <<<"$(valid_serials)" || { echo "new cert not valid on chain" >&2; false; }

  seq1=$(seq_now)
  restart_pod
  wait_healthy
  expect_eq "$(seq_now)" "$seq1" "transactions on the next restart"
}

@test "08 certificate revoked on chain: new certificate published with 1 transaction" {
  local seq0 serial0 serial1
  seq0=$(seq_now); serial0=$(local_serial)

  node akash tx cert revoke server --serial "$serial0" --from provider --keyring-backend test \
    --chain-id localnet-1 --gas auto --gas-adjustment 1.5 --gas-prices 0.025uakt -b sync -y >/dev/null
  wait_seq "$((seq0 + 1))"
  ! grep -qx "$serial0" <<<"$(valid_serials)" || { echo "test setup: cert $serial0 still valid" >&2; false; }

  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy

  expect_eq "$(seq_now)" "$((seq0 + 2))" "transactions (test revoke + publish cert)"
  serial1=$(local_serial)
  [[ "$serial1" != "$serial0" ]] || { echo "certificate was not regenerated" >&2; false; }
  grep -qx "$serial1" <<<"$(valid_serials)" || { echo "new cert $serial1 not valid on chain" >&2; false; }
}

@test "09 wrong key passphrase on an existing volume: init stops with a clear error" {
  local seq0 uid0
  seq0=$(seq_now); uid0=$(pod_uid)

  upgrade_provider --set keysecret="$(printf 'wrong-pass' | base64)"
  kubectl -n "$PROVIDER_NS" delete pod "$PROVIDER_POD" --wait=false >/dev/null
  wait_init_failed "$uid0"
  run init_failed_log
  grep -q "ERROR cannot read the key from .Values.key" <<<"$output" || { echo "init log does not explain the failure" >&2; false; }
  ! grep -q "\[wait for RPC\]" <<<"$output" || { echo "init went on after the error" >&2; false; }

  upgrade_provider --set keysecret="$(printf 'localnet-pass' | base64)"
  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code with the right passphrase"
  wait_healthy
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "10 from is another account's address: init stops with a clear error, recovers when restored" {
  local seq0 uid0
  seq0=$(seq_now); uid0=$(pod_uid)

  upgrade_provider --set from="$(validator_addr)"
  wait_init_failed "$uid0"
  run init_failed_log
  grep -q "ERROR .Values.from has the form of an address, but it is not the address of the key in .Values.key" <<<"$output" || { echo "init log does not explain the mismatch" >&2; false; }
  ! grep -q "\[wait for RPC\]" <<<"$output" || { echo "init went on after the error" >&2; false; }
  grep -q "ERROR   found: .Values.from=$(validator_addr), address of the key=$(addr)" <<<"$output" || { echo "init log does not print both addresses" >&2; false; }
  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$(addr)")" "keys on the volume unchanged"

  upgrade_provider --set from="$(addr)"
  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code after restoring from"
  wait_healthy
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "11 PVC lost: wrong passphrase stops init; right one re-imports the key, no transactions" {
  local seq0 serial0
  seq0=$(seq_now); serial0=$(local_serial)

  upgrade_provider --set keysecret="$(printf 'wrong-pass' | base64)"
  kubectl -n "$PROVIDER_NS" scale statefulset akash-provider --replicas=0 >/dev/null
  kubectl -n "$PROVIDER_NS" wait --for=delete "pod/$PROVIDER_POD" --timeout=120s >/dev/null
  kubectl -n "$PROVIDER_NS" delete pvc "home-$PROVIDER_POD" --wait >/dev/null
  kubectl -n "$PROVIDER_NS" scale statefulset akash-provider --replicas=1 >/dev/null

  wait_init_failed none
  run init_failed_log
  grep -q "ERROR cannot read the key from .Values.key" <<<"$output" || { echo "init log does not explain the failed import" >&2; false; }
  ! grep -q "\[wait for RPC\]" <<<"$output" || { echo "init went on after the error" >&2; false; }

  upgrade_provider --set keysecret="$(printf 'localnet-pass' | base64)"
  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code with the right passphrase"
  wait_healthy

  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$(addr)")" "key re-imported on the new PVC"
  expect_eq "$(local_serial)" "$serial0" "certificate on the node reused"
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "12 attributes reordered in values: rollout, no transactions" {
  local seq0 uid0 values
  seq0=$(seq_now); uid0=$(pod_uid)
  values="$BATS_TEST_TMPDIR/attributes.yaml"
  cat >"$values" <<'YAML'
attributes:
- key: host
  value: akash
- key: region
  value: localnet-2
YAML

  upgrade_provider -f "$values"
  wait_new_pod "$uid0"
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "13 from is a key name: provider keeps running as the key's address, no transactions" {
  local seq0 uid0
  seq0=$(seq_now); uid0=$(pod_uid)

  upgrade_provider --set from=provider
  wait_new_pod "$uid0"
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
  grep -q "INFO  .Values.from \"provider\" is used as the key name; provider address (from the key): $(addr)" <<<"$output" ||
    { echo "init log does not explain the key name" >&2; false; }
  expect_eq "$(seq_now)" "$seq0" "transactions"

  restart_pod
  wait_healthy
  expect_eq "$(seq_now)" "$seq0" "transactions on the next restart (no owner-only update)"

  uid0=$(pod_uid)
  upgrade_provider --set from="$(addr)"
  wait_new_pod "$uid0"
  wait_healthy
}

@test "14 chain read errors stop the step and are never taken as 'not found'" {
  local seq0
  seq0=$(seq_now)
  # a copy of the akt config pointing at an RPC endpoint that refuses connections
  run prov bash -c '
    mkdir -p /tmp/akt-bad && cp "$AKT_HOME/config.yaml" /tmp/akt-bad/ && export AKT_HOME=/tmp/akt-bad
    akt context network edit provider --rpc http://127.0.0.1:1 >/dev/null
    source /scripts/provider_record.sh
    ensure_provider '"$(addr)"
  [[ "$status" -ne 0 ]] || { echo "ensure_provider did not fail" >&2; false; }
  grep -q "chain query failed (try 1/3)" <<<"$output" || { echo "no retry logged" >&2; echo "$output" >&2; false; }
  grep -q "ERROR cannot read from the chain" <<<"$output" || { echo "no clear error" >&2; false; }
  ! grep -q "not on chain: creating it" <<<"$output" || { echo "a chain error was taken as 'not found'" >&2; false; }

  run prov bash -c '
    export AKT_HOME=/tmp/akt-bad
    source /scripts/provider_cert.sh
    cert_state '"$(addr)"
  [[ "$status" -ne 0 ]] || { echo "cert_state did not fail" >&2; false; }
  grep -q "ERROR cannot read from the chain" <<<"$output" || { echo "no clear error from cert_state" >&2; false; }
  prov rm -rf /tmp/akt-bad
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "15 create for an existing provider: rejected before broadcast, no fee" {
  local seq0
  seq0=$(seq_now)
  run prov bash -c 'source /scripts/provider_record.sh; write_provider_file; send_tx akt tx provider create "$PROVIDER_FILE" --from '"$(addr)"' -y'
  [[ "$status" -ne 0 ]] || { echo "duplicate create did not fail" >&2; false; }
  grep -q "ERROR transaction failed" <<<"$output" || { echo "no clear error" >&2; echo "$output" >&2; false; }
  grep -q "already exists" <<<"$output" || { echo "reason not shown" >&2; false; }
  expect_eq "$(seq_now)" "$seq0" "transactions"
}

@test "16 other provider's key with allowIdentityChange=false: init stops, nothing changes" {
  local seq0 vseq0 uid0
  seq0=$(seq_now); vseq0=$(seq_of "$(validator_addr)"); uid0=$(pod_uid)

  upgrade_provider --set from="$(validator_addr)" --set key="$(validator_key_b64)" \
    --set keysecret="$(printf 'validator-pass' | base64)" --set allowIdentityChange=false
  wait_init_failed "$uid0"
  run init_failed_log
  grep -q "ERROR identity change blocked (.Values.allowIdentityChange=false)" <<<"$output" || { echo "init log does not explain the block" >&2; false; }
  grep -q "the volume holds the key of $(addr), .Values.key holds the key of $(validator_addr)" <<<"$output" ||
    { echo "init log does not name both providers" >&2; false; }
  ! grep -q "\[wait for RPC\]" <<<"$output" || { echo "init went on after the error" >&2; false; }

  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$(addr)")" "keys on the volume unchanged"
  expect_eq "$(seq_now)" "$seq0" "transactions of the provider"
  expect_eq "$(seq_of "$(validator_addr)")" "$vseq0" "transactions of the other account"
}

@test "17 other provider's key with allowIdentityChange=true: switches with a warning, old keystore kept aside" {
  local vseq0 new
  new=$(validator_addr); vseq0=$(seq_of "$new")

  upgrade_provider --set allowIdentityChange=true
  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy

  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
  grep -q "WARN  provider identity changes on this volume" <<<"$output" || { echo "no warning" >&2; false; }
  grep -q "WARN    was: $(addr)" <<<"$output" || { echo "warning does not name the old provider" >&2; false; }
  grep -q "WARN    now: $new" <<<"$output" || { echo "warning does not name the new provider" >&2; false; }

  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$new")" "keys on the volume: only the new provider"
  docker exec "$KIND_NODE" sh -c "ls -d $(pvc_dir)/keyring-test.backup-$(addr)-*" >/dev/null ||
    { echo "old keystore not kept aside" >&2; false; }
  expect_eq "$(seq_of "$new")" "$((vseq0 + 2))" "transactions of the new provider (create, publish cert)"
  [[ -n "$(node akash query provider get "$new" -o json 2>/dev/null)" ]] || { echo "new provider not on chain" >&2; false; }
  [[ -n "$(provider_json)" ]] || { echo "old provider record gone" >&2; false; }
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c provider
  grep -q "starting: /usr/bin/provider-services run --from $new" <<<"$output" || { echo "daemon not started as the new provider" >&2; false; }
}
