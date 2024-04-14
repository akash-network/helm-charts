#!/bin/bash
# Filename: init.sh

if [[ $AKASH_DEBUG == "true" ]]; then sleep 5000; fi

set -x

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
