#!/bin/bash
# Filename: init.sh
#
# Init container: sets up the provider identity on the volume, then makes sure the provider record and
# its certificate are on chain. Configuration errors stop it before any chain call.

source /scripts/lib.sh
source /scripts/identity.sh
source /scripts/provider_record.sh
source /scripts/provider_cert.sh

log_step "akt context"
/scripts/akt_context.sh

log_step "identity"
PROVIDER_ADDRESS=$(ensure_identity)

log_step "wait for RPC"
/scripts/wait_for_rpc.sh

log_step "provider"
ensure_provider "$PROVIDER_ADDRESS"

log_step "certificate"
ensure_cert "$PROVIDER_ADDRESS"

log_info "init done: provider $PROVIDER_ADDRESS"
