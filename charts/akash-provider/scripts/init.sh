#!/bin/bash
# Filename: init.sh

if [[ $AKASH_DEBUG == "true" ]]; then sleep 5000; fi

set -x

##
# Check storage class availability (if Let's Encrypt is enabled)
##
if [[ "${AP_CERT_ISSUER_ENABLED}" == "true" ]]; then
  echo "Let's Encrypt enabled - checking storage class availability..."
  
  # Get the storage class from provider attributes or use default
  STORAGE_CLASS=""
  if [[ -n "${PROVIDER_STORAGE_CLASS}" ]]; then
    STORAGE_CLASS="${PROVIDER_STORAGE_CLASS}"
  else
    STORAGE_CLASS="local-path"
  fi
  
  echo "Checking for storage class: ${STORAGE_CLASS}"
  
  # Check if any storage classes exist
  STORAGE_CLASS_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
  if [[ "$STORAGE_CLASS_COUNT" -eq 0 ]]; then
    echo "ERROR: No storage classes found in the cluster!"
    echo ""
    echo "The Let's Encrypt PVC requires a storage class to be available."
    echo "Please install the Rancher Local Path Provisioner:"
    echo ""
    echo "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml"
    echo ""
    echo "For more information, visit: https://github.com/rancher/local-path-provisioner"
    echo ""
    echo "After installing the storage provisioner, restart the provider pod."
    exit 1
  fi
  
  # Check if the specific storage class exists
  if ! kubectl get storageclass "${STORAGE_CLASS}" >/dev/null 2>&1; then
    echo "WARNING: Storage class '${STORAGE_CLASS}' not found!"
    echo ""
    echo "Available storage classes:"
    kubectl get storageclass
    echo ""
    echo "The Let's Encrypt PVC will use the default storage class."
    echo "Consider updating your provider attributes to use an available storage class."
  else
    echo "Storage class '${STORAGE_CLASS}' found. Validation passed."
  fi
fi

##
# Import key
##
cat "$AKASH_BOOT_KEYS/key-pass.txt" | { cat ; echo ; } | provider-services --home="$AKASH_HOME" keys import --keyring-backend="$AKASH_KEYRING_BACKEND"  "$AKASH_FROM" "$AKASH_BOOT_KEYS/key.txt"

##
# Wait for RPC
##
/scripts/wait_for_rpc.sh

##
# Create/Update Provider
##
/scripts/create_provider.sh

##
# Create/Update Provider certs
##
/scripts/refresh_provider_cert.sh
