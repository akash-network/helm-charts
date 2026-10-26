# Helpers for the akash-provider chart e2e suite (bats).
# The environment comes from ../Makefile: kind cluster, localnet chain, provider chart.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$ROOT/.cache/kubeconfig}"

CHARTS="$(cd "$ROOT/../../charts" && pwd)"
PROVIDER_NS=akash-services
PROVIDER_POD=akash-provider-0
LOCALNET_NS=akash-localnet
LOCALNET_POD=akash-node-1-0
KIND_NODE=akash-provider-e2e-control-plane
CERT_PATH=/config/provider.pem
DOMAIN=provider.localnet.test

# Provider address of the current chain (written by `make provider-key`).
addr() { cat "$ROOT/.cache/provider/address"; }

# Commands in the localnet node (its keyring holds the provider key too).
node() { kubectl -n "$LOCALNET_NS" exec "$LOCALNET_POD" -c akash-node -- "$@"; }

# Commands in the provider (main) container.
prov() { kubectl -n "$PROVIDER_NS" exec "$PROVIDER_POD" -c provider -- "$@"; }

pod_json() { kubectl -n "$PROVIDER_NS" get pod "$PROVIDER_POD" -o json; }

# --- chain state

# Account sequence = number of transactions the provider key has signed.
seq_now() { node akash query auth account "$(addr)" -o json | jq -r .account.sequence; }

# Wait until the sequence reaches $1 (transactions are broadcast in sync mode by the tests).
wait_seq() {
  local want=$1 i
  for i in $(seq 1 30); do
    [[ "$(seq_now)" -ge "$want" ]] && return 0
    sleep 1
  done
  echo "account sequence $(seq_now), expected >= $want" >&2
  return 1
}

provider_json() { node akash query provider get "$(addr)" -o json; }

# Serial numbers (decimal) of the provider's valid certificates on chain.
valid_serials() {
  node akash query cert list --owner "$(addr)" --state valid -o json | jq -r '.certificates[].serial'
}

# --- provider certificate on the kind node (hostPath /root/.akash/k8s-config = /config)

# Serial (decimal) of /config/provider.pem, as refresh_provider_cert.sh computes it.
local_serial() {
  local hex
  hex=$(prov openssl x509 -serial -noout -in "$CERT_PATH" | cut -d= -f2)
  echo "obase=10; ibase=16; $hex" | BC_LINE_LENGTH=0 bc
}

# True when /config/provider.pem is still valid in $1 seconds.
local_cert_valid_for() { prov openssl x509 -checkend "$1" -noout -in "$CERT_PATH" >/dev/null; }

rm_node_cert() { docker exec "$KIND_NODE" rm -f /root/.akash/k8s-config/provider.pem; }

# --- pod state

pod_uid() { kubectl -n "$PROVIDER_NS" get pod "$PROVIDER_POD" -o jsonpath='{.metadata.uid}' 2>/dev/null; }
init_started() { pod_json | jq -r '.status.initContainerStatuses[0].state.terminated.startedAt // empty'; }
init_exit_code() { pod_json | jq -r '.status.initContainerStatuses[0].state.terminated.exitCode // empty'; }
# Exit code of the init container's latest finished run, also while it waits in CrashLoopBackOff.
init_last_exit_code() {
  pod_json | jq -r '.status.initContainerStatuses[0] | (.state.terminated.exitCode // .lastState.terminated.exitCode // empty)'
}
main_restarts() { pod_json | jq -r '.status.containerStatuses[0].restartCount'; }

# Log of the init container's latest finished run. For a terminated or crash-looping
# container this is the plain log; --previous may already be gone (and still exit 0).
init_failed_log() { kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init; }

# akt config.yaml straight from the PVC on the kind node (readable while the pod crash-loops).
pvc_akt_config() {
  local pv
  pv=$(kubectl -n "$PROVIDER_NS" get pvc "home-$PROVIDER_POD" -o jsonpath='{.spec.volumeName}')
  docker exec "$KIND_NODE" sh -c "cat /var/local-path-provisioner/${pv}_${PROVIDER_NS}_home-${PROVIDER_POD}/config.yaml"
}

# Wait for a pod other than uid $1 whose init container has failed (exit code 1).
wait_init_failed() {
  local old=$1 i
  for i in $(seq 1 60); do
    if [[ "$(pod_uid)" != "$old" && "$(init_last_exit_code)" == 1 ]]; then return 0; fi
    sleep 2
  done
  echo "no new pod with a failed init container" >&2
  return 1
}

# Addresses (hex) of the keys in the keystore on the volume, read on the node (works while init fails).
pvc_dir() {
  local pv
  pv=$(kubectl -n "$PROVIDER_NS" get pvc "home-$PROVIDER_POD" -o jsonpath='{.spec.volumeName}')
  echo "/var/local-path-provisioner/${pv}_${PROVIDER_NS}_home-${PROVIDER_POD}"
}
pvc_key_hexes() {
  docker exec "$KIND_NODE" sh -c "ls $(pvc_dir)/keyring-test 2>/dev/null" | sed -n 's/\.address$//p' | sort | tr '\n' ' ' | sed 's/ $//'
}
addr_hex() { node akash debug addr "$1" 2>&1 | sed -n 's/^Address (hex): //p' | tr 'A-F' 'a-f'; }

# The localnet validator: a funded account other than the provider, used as "another provider".
validator_addr() { node akash keys show validator -a --keyring-backend test; }
validator_key_b64() {
  node sh -c "printf 'validator-pass\nvalidator-pass\n' | akash keys export validator --keyring-backend test" 2>/dev/null | base64 | tr -d '\n'
}
seq_of() { node akash query auth account "$1" -o json | jq -r .account.sequence; }

# Healthy = the chart's own liveness checks pass in the provider container.
wait_healthy() {
  local i
  for i in $(seq 1 60); do
    prov timeout 40 /scripts/liveness_checks.sh >/dev/null 2>&1 && return 0
    sleep 3
  done
  echo "provider not healthy" >&2
  return 1
}

# Wait for a pod other than uid $1 whose init container finished.
wait_new_pod() {
  local old=$1 i
  for i in $(seq 1 60); do
    if [[ -n "$(pod_uid)" && "$(pod_uid)" != "$old" && -n "$(init_exit_code)" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "no new pod with a finished init container" >&2
  return 1
}

restart_pod() {
  local old
  old=$(pod_uid)
  kubectl -n "$PROVIDER_NS" delete pod "$PROVIDER_POD" --wait=false >/dev/null
  wait_new_pod "$old"
}

# helm upgrade of the provider chart, keeping the installed values (key, keysecret, from).
upgrade_provider() {
  helm upgrade akash-provider "$CHARTS/akash-provider" -n "$PROVIDER_NS" --reuse-values "$@" >/dev/null
}

# --- diagnostics on failure

dump_state() {
  {
    echo "--- pods"
    kubectl -n "$PROVIDER_NS" get pods -o wide
    echo "--- init container status"
    pod_json | jq -c '.status.initContainerStatuses[0] | {restartCount, state, lastState}'
    echo "--- init log (latest finished run)"
    kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c init
    echo "--- akt config.yaml on the PVC"
    pvc_akt_config
    echo "--- provider log (tail)"
    kubectl -n "$PROVIDER_NS" logs "$PROVIDER_POD" -c provider --tail=20
    echo "--- account sequence: $(seq_now)"
  } 2>&1 | sed 's/^/# /' >&3
}
