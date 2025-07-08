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

# Add certificate issuer flags if enabled
if [[ "${CERT_ISSUER_ENABLED}" == "true" ]]; then
    PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-enabled=true"
    
    if [[ -n "${CERT_ISSUER_DNS_PROVIDERS}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-dns-providers=${CERT_ISSUER_DNS_PROVIDERS}"
    fi
    
    if [[ -n "${CERT_ISSUER_EMAIL}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-email=${CERT_ISSUER_EMAIL}"
    fi
    
    if [[ -n "${CERT_ISSUER_CA_DIR_URL}" ]]; then
        PROVIDER_CMD="${PROVIDER_CMD} --cert-issuer-ca-dir-url=${CERT_ISSUER_CA_DIR_URL}"
    fi
fi

# Start provider-services and monitor its output
eval "${PROVIDER_CMD}"
