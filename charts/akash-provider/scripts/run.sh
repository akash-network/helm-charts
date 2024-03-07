#!/bin/bash

# Install apps required by the bid price script
apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install curl jq bc mawk ca-certificates

# fail fast should there be a problem installing curl / jq packages
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

# Start provider-services and monitor its output
exec provider-services run | while read line; do
    echo "$line"
    if [[ "$line" == *"account sequence mismatch"* ]]; then
        echo "Pattern 'account sequence mismatch' found. Restarting provider-services..."
        exit 2
    fi
done
