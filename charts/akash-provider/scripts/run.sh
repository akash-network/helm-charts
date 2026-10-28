#!/bin/bash
# Filename: run.sh
#
# Main container: checks the provider key and certificate, then starts the daemon as the provider
# whose key is on the volume (set up by the init container).

source /scripts/lib.sh
source /scripts/identity.sh
source /scripts/provider_cert.sh

log_step "akt context"
/scripts/akt_context.sh

log_step "identity"
PROVIDER_ADDRESS=$(volume_addresses)
if [[ -z "$PROVIDER_ADDRESS" || "$PROVIDER_ADDRESS" == *" "* ]]; then
  fail "expected the key of exactly one provider on the volume" "keys of: ${PROVIDER_ADDRESS:-none}" \
    "check the init container log"
fi
log_info "provider: $PROVIDER_ADDRESS"

log_step "wait for RPC"
/scripts/wait_for_rpc.sh

log_step "certificate"
ensure_cert "$PROVIDER_ADDRESS"

log_step "start"
cmd=(/usr/bin/provider-services run --from "$PROVIDER_ADDRESS")
if [[ "${AP_CERT_ISSUER_ENABLED:-}" == "true" ]]; then
  cmd+=(--cert-issuer-enabled=true)
  [[ -n "${AP_CERT_ISSUER_EMAIL:-}" ]] && cmd+=(--cert-issuer-email="$AP_CERT_ISSUER_EMAIL")
  [[ -n "${AP_CERT_ISSUER_CA_DIR_URL:-}" ]] && cmd+=(--cert-issuer-ca-dir-url="$AP_CERT_ISSUER_CA_DIR_URL")
  [[ -n "${AP_CERT_ISSUER_DNS_PROVIDERS:-}" ]] && cmd+=(--cert-issuer-dns-providers="$AP_CERT_ISSUER_DNS_PROVIDERS")
  [[ -n "${AP_CERT_ISSUER_HTTP_CHALLENGE_PORT:-}" ]] && cmd+=(--cert-issuer-http-challenge-port="$AP_CERT_ISSUER_HTTP_CHALLENGE_PORT")
fi

if [[ "${AKASH_DEBUG:-false}" == "true" ]]; then
  if [[ -x /go/bin/dlv ]]; then
    cmd=(/go/bin/dlv "--listen=:${AKASH_DEBUG_DELVE_PORT:-2345}" --headless=true --api-version=2 --log exec -- "${cmd[@]}")
  else
    log_warn "AKASH_DEBUG is set, but there is no dlv in the image (use the image with the debug suffix)"
  fi
fi

log_info "starting: ${cmd[*]}"
exec "${cmd[@]}"
