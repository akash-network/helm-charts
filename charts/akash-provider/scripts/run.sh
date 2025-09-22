#!/bin/bash

# fail fast should these packages be missing
type curl || exit 1
type jq || exit 1
type awk || exit 1
type bc || exit 1

##
# Wait for RPC
##
/scripts/wait_for_rpc.sh

##
# Create/Update Provider certs
##
/scripts/refresh_provider_cert.sh

# Build provider-services run command with optional certificate issuer flags
PROVIDER_CMD="provider-services run"

# Add certificate issuer flags if enabled (HTTP challenge default, DNS providers optional)
if [[ "${AP_CERT_ISSUER_ENABLED}" == "true" ]]; then
    PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-enabled=true"
    
    if [[ -n "${AP_CERT_ISSUER_EMAIL}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-email=${AP_CERT_ISSUER_EMAIL}"
    fi
    
    if [[ -n "${AP_CERT_ISSUER_CA_DIR_URL}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-ca-dir-url=${AP_CERT_ISSUER_CA_DIR_URL}"
    fi
    
    if [[ -n "${AP_CERT_ISSUER_DNS_PROVIDERS}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-dns-providers=${AP_CERT_ISSUER_DNS_PROVIDERS}"
    fi
    
    if [[ -n "${AP_CERT_ISSUER_HTTP_CHALLENGE_PORT}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-http-challenge-port=${AP_CERT_ISSUER_HTTP_CHALLENGE_PORT}"
    fi
fi

# Debug: Print the final command to see all flags
echo "=== Provider Command Debug ==="
echo "AP_CERT_ISSUER_ENABLED: ${AP_CERT_ISSUER_ENABLED}"
echo "AP_CERT_ISSUER_EMAIL: ${AP_CERT_ISSUER_EMAIL}"
echo "AP_CERT_ISSUER_CA_DIR_URL: ${AP_CERT_ISSUER_CA_DIR_URL}"
echo "AP_CERT_ISSUER_DNS_PROVIDERS: ${AP_CERT_ISSUER_DNS_PROVIDERS}"
echo "AP_CERT_ISSUER_HTTP_CHALLENGE_PORT: ${AP_CERT_ISSUER_HTTP_CHALLENGE_PORT}"
echo "Final command: ${PROVIDER_CMD}"
echo "=============================="

# Start provider-services and monitor its output
${PROVIDER_CMD}
