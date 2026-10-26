#!/bin/bash
# Filename: akt_context.sh
#
# akt configuration on the volume ($AKT_HOME = .Values.home), using the keystore the daemon uses.
# Created when missing; the chain endpoint and gas settings follow the values on every start.
# Which provider key the volume holds is decided by identity.sh, not here.

source /scripts/lib.sh

CTX=provider

if ! akt context network show "$CTX" >/dev/null 2>&1; then
  akt context network create "$CTX" --chain-id "$AKASH_CHAIN_ID" --rpc "$AKASH_NODE" >/dev/null
  log_info "akt network \"$CTX\" created"
fi
if ! akt context keyring list -o json | jq -e --arg n "$CTX" 'any(.[]; .name == $n)' >/dev/null; then
  akt context keyring create "$CTX" "$AKT_KEYRING_BACKEND" --dir "$AKT_HOME" >/dev/null
  log_info "akt keyring \"$CTX\" created (backend $AKT_KEYRING_BACKEND, dir $AKT_HOME)"
fi
if ! akt context list -o json | jq -e --arg n "$CTX" 'any(.[]; .name == $n)' >/dev/null; then
  akt context create "$CTX" --network "$CTX" --keyring "$CTX" --set-current >/dev/null
  log_info "akt context \"$CTX\" created"
fi

akt context network edit "$CTX" --chain-id "$AKASH_CHAIN_ID" --rpc "$AKASH_NODE" \
  --gas-prices "$AKT_GAS_PRICES" --gas-adjustment "$AKT_GAS_ADJUSTMENT" >/dev/null
akt context edit "$CTX" --gas "$AKT_GAS" >/dev/null
log_info "akt context ready: chain $AKASH_CHAIN_ID, rpc $AKASH_NODE"
