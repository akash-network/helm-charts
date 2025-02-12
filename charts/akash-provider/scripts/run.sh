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

# Start provider-services and monitor its output
provider-services run
