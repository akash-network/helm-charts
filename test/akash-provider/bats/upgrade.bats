#!/usr/bin/env bats
# Upgrade from the released chart ($RELEASED_CHART, set by `make test-upgrade`) to the chart on this
# branch, with the provider volume kept. Each test starts from a fresh chain and volume.

load helpers

VALUES="$ROOT/localnet/provider-values.yaml"

setup() {
  make -s -C "$ROOT" e2e-reset hostname-operator inventory-operator provider-key >/dev/null 2>&1
}

teardown() {
  if [[ -z "${BATS_TEST_COMPLETED:-}" ]]; then dump_state; fi
}

expect_eq() {
  [[ "$1" == "$2" ]] || { echo "$3: got '$1', want '$2'" >&2; return 1; }
}

key_b64() { base64 < "$ROOT/.cache/provider/key.txt" | tr -d '\n'; }
pass_b64() { printf 'localnet-pass' | base64; }

# deploy <chart> <helm args...>: installs or upgrades the provider, waits for a new pod whose init finished.
deploy() {
  local chart=$1 uid0
  shift
  uid0=$(pod_uid || true); uid0=${uid0:-none}   # no pod yet on a first install
  helm upgrade --install akash-provider "$chart" -n "$PROVIDER_NS" -f "$VALUES" "$@" >/dev/null
  wait_new_pod "$uid0"
}

@test "U1 released volume: upgrade is a normal restart, no transactions, same certificate" {
  deploy "$RELEASED_CHART" --set from="$(addr)" --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  expect_eq "$(init_exit_code)" 0 "released chart: init exit code"
  wait_healthy
  local seq0 serial0
  seq0=$(seq_now); serial0=$(local_serial)

  deploy "$CHARTS/akash-provider" --set from="$(addr)" --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  expect_eq "$(init_exit_code)" 0 "branch chart: init exit code"
  wait_healthy

  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
  grep -q "INFO  provider key already on the volume" <<<"$output" || { echo "not a normal restart" >&2; echo "$output" >&2; false; }
  grep -q "INFO  provider on chain, up to date" <<<"$output" || { echo "provider record not up to date" >&2; false; }
  expect_eq "$(seq_now)" "$seq0" "transactions"
  expect_eq "$(local_serial)" "$serial0" "certificate kept"
  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$(addr)")" "keys on the volume"
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c provider
  grep -q "starting: /usr/bin/provider-services run --from $(addr)" <<<"$output" || { echo "daemon not started with the address" >&2; false; }

}

@test "U2 released volume with the key under a second name: normal restart, no transactions" {
  deploy "$RELEASED_CHART" --set from="$(addr)" --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  wait_healthy
  # 0.16.4 with from as a key name stores the same key a second time under that name
  deploy "$RELEASED_CHART" --set from=provider --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  wait_healthy
  local seq0
  seq0=$(seq_now)

  deploy "$CHARTS/akash-provider" --set from="$(addr)" --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  expect_eq "$(init_exit_code)" 0 "branch chart: init exit code"
  wait_healthy
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
  grep -q "INFO  provider key already on the volume" <<<"$output" || { echo "not a normal restart" >&2; echo "$output" >&2; false; }
  expect_eq "$(seq_now)" "$seq0" "transactions"
  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$(addr)")" "keys on the volume (one address)"
}

@test "U3 released volume after an identity switch: blocked with allowIdentityChange=false, else warned and cleaned" {
  local new uid0 nseq0
  new=$(validator_addr)
  deploy "$RELEASED_CHART" --set from="$(addr)" --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  wait_healthy
  # 0.16.4: new from + new key switch the provider and leave the old key on the volume
  deploy "$RELEASED_CHART" --set from="$new" --set key="$(validator_key_b64)" --set keysecret="$(printf 'validator-pass' | base64)"
  wait_healthy
  nseq0=$(seq_of "$new")
  expect_eq "$(pvc_key_hexes)" "$(printf '%s\n' "$(addr_hex "$(addr)")" "$(addr_hex "$new")" | sort | tr '\n' ' ' | sed 's/ $//')" "released volume holds both keys"

  uid0=$(pod_uid)
  helm upgrade akash-provider "$CHARTS/akash-provider" -n "$PROVIDER_NS" -f "$VALUES" --set from="$new" \
    --set key="$(validator_key_b64)" --set keysecret="$(printf 'validator-pass' | base64)" --set allowIdentityChange=false >/dev/null
  wait_init_failed "$uid0"
  run init_failed_log
  grep -q "ERROR identity change blocked (.Values.allowIdentityChange=false)" <<<"$output" || { echo "not blocked" >&2; echo "$output" >&2; false; }

  helm upgrade akash-provider "$CHARTS/akash-provider" -n "$PROVIDER_NS" --reuse-values --set allowIdentityChange=true >/dev/null
  restart_pod
  expect_eq "$(init_exit_code)" 0 "init exit code with allowIdentityChange=true"
  wait_healthy
  run kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
  grep -q "WARN  provider identity changes on this volume" <<<"$output" || { echo "no warning" >&2; echo "$output" >&2; false; }
  expect_eq "$(pvc_key_hexes)" "$(addr_hex "$new")" "keys on the volume: only the current provider"
  expect_eq "$(seq_of "$new")" "$nseq0" "transactions of the current provider (record and certificate already on chain)"
}

@test "U4 operator upgrades straight from the released release with --reuse-values" {
  local uid0
  deploy "$RELEASED_CHART" --set from="$(addr)" --set key="$(key_b64)" --set keysecret="$(pass_b64)"
  wait_healthy
  uid0=$(pod_uid)

  helm upgrade akash-provider "$CHARTS/akash-provider" -n "$PROVIDER_NS" --reuse-values >/dev/null
  wait_new_pod "$uid0"
  expect_eq "$(init_exit_code)" 0 "init exit code"
  wait_healthy
  echo "# values after --reuse-values from the released release:" \
    "ALLOW_IDENTITY_CHANGE=\"$(kubectl -n "$PROVIDER_NS" get cm akash-provider-init -o jsonpath='{.data.ALLOW_IDENTITY_CHANGE}')\"" \
    "AKASH_DEPLOYMENT_NETWORK_POLICIES_ENABLED=\"$(kubectl -n "$PROVIDER_NS" get cm akash-provider-main -o jsonpath='{.data.AKASH_DEPLOYMENT_NETWORK_POLICIES_ENABLED}')\"" \
    "deploymentnetworkpoliciesenabled in release values: $(helm get values akash-provider -n "$PROVIDER_NS" -a -o json | jq -c .deploymentnetworkpoliciesenabled)" >&3
}
