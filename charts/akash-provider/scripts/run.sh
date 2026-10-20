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
PROVIDER_CMD="/usr/bin/provider-services run"
CC_ARGS=()

# These are public, operator-controlled inputs. Tenant key material remains a
# sealed SDL value and is never mounted into the Provider pod.
if [[ -n "${AP_CC_KBS_URL:-}" ]]; then
    CC_ARGS+=("--cc-kbs-url=${AP_CC_KBS_URL}")
    CC_ARGS+=("--cc-kbs-cert-file=${AP_CC_KBS_CERT_FILE}")
    CC_ARGS+=("--cc-image-security-policy-uri=${AP_CC_IMAGE_SECURITY_POLICY_URI}")
    CC_ARGS+=("--cc-agent-policy-file=${AP_CC_AGENT_POLICY_FILE}")
fi

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
printf 'Final command: %s' "${PROVIDER_CMD}"
printf ' %q' "${CC_ARGS[@]}"
printf '\n'
echo "=============================="

# Start provider-services and monitor its output
runcmd=${PROVIDER_CMD}

run_debug=${AKASH_DEBUG:-false}
dlv_port=${AKASH_DEBUG_DELVE_PORT:-2345}

if [[ $run_debug == "true" ]]; then
    if command /go/bin/dlv; then
        runcmd="/go/bin/dlv --listen=:${dlv_port} --headless=true --api-version=2 --log exec -- ${PROVIDER_CMD}"
    else
        echo "AKASH_DEBUG is set, but no dlv is present in the image. check if docker image has debug suffix"
    fi
fi

${runcmd} "${CC_ARGS[@]}"
