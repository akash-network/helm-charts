#!/bin/bash
# Filename: identity.sh
#
# Which provider this volume runs as. Sourced by init.sh (ensure_identity) and run.sh (volume_addresses).
#
# The key in the keys Secret (key/keysecret) is the source of truth; the provider address is derived
# from it. The keystore on the volume holds the key of exactly one provider. `from` may be the provider
# address or any key name, as in earlier chart versions; it is checked, but never picks the key.

source /scripts/lib.sh

KEYSTORE_DIR="$AKT_HOME/keyring-$AKT_KEYRING_BACKEND"

# check_from_format: stops if .Values.from is empty or cannot be used as a key name (spaces, "/").
check_from_format() {
  if [[ -z "${AKT_FROM// }" ]]; then
    fail ".Values.from is empty" ".Values.from=\"\"" "set .Values.from to the provider address or a key name"
  fi
  if [[ "$AKT_FROM" == *" "* || "$AKT_FROM" == */* ]]; then
    fail ".Values.from cannot be used as a key name" ".Values.from=\"$AKT_FROM\"" "use the provider address or a name without spaces or \"/\""
  fi
}

# secret_address: address of the key in the keys Secret. The key is decrypted into a temporary
# keystore under /tmp, which is removed again; the volume is not touched.
secret_address() {
  local dir address
  dir=$(mktemp -d)
  if ! cat "$AKASH_BOOT_KEYS/key-pass.txt" | { cat; echo; } |
    akt context keys import secret "$AKASH_BOOT_KEYS/key.txt" --keyring-dir "$dir" --keyring-backend test >/dev/null 2>"$dir.err"; then
    local reason
    reason=$(sed 's/^Enter passphrase to decrypt the key: //' "$dir.err" | tail -1)
    rm -rf "$dir" "$dir.err"
    fail "cannot read the key from .Values.key" "$reason" "check .Values.key and .Values.keysecret"
  fi
  address=$(akt context keys show secret -a --keyring-dir "$dir" --keyring-backend test)
  rm -rf "$dir" "$dir.err"
  echo "$address"
}

# check_from <address of the Secret key>: compares .Values.from with that address. Logs how from is
# used (the address itself, or a key name); stops if from has the form of another address.
check_from() {
  local secret=$1
  if [[ "$AKT_FROM" == "$secret" ]]; then
    log_info ".Values.from matches the key: $secret"
  elif is_address "$AKT_FROM"; then
    fail ".Values.from has the form of an address, but it is not the address of the key in .Values.key" \
      ".Values.from=$AKT_FROM, address of the key=$secret" \
      "set .Values.from to $secret (or to a key name), or put the key of $AKT_FROM into .Values.key/.Values.keysecret"
  else
    log_info ".Values.from \"$AKT_FROM\" is used as the key name; provider address (from the key): $secret"
  fi
}

# volume_addresses: distinct addresses of the keys in the keystore on the volume, space-separated
# (one key stored under several names counts once).
volume_addresses() {
  akt context keys list -o json | jq -r '[.[].address] | unique | join(" ")'
}

# import_key: imports the key from the keys Secret into the keystore on the volume, under the name
# given by .Values.from. Stops if the import fails.
import_key() {
  if ! cat "$AKASH_BOOT_KEYS/key-pass.txt" | { cat; echo; } |
    akt context keys import "$AKT_FROM" "$AKASH_BOOT_KEYS/key.txt" >/dev/null 2>&1; then
    fail "cannot import the key from .Values.key into $KEYSTORE_DIR" "import failed" "check the volume"
  fi
  log_info "key from .Values.key imported into $KEYSTORE_DIR (key name \"$AKT_FROM\" from .Values.from)"
}

# move_keystore_aside <old addresses>: keeps the previous provider's keys in a backup directory.
move_keystore_aside() {
  local backup
  backup="$KEYSTORE_DIR.backup-${1%% *}-$(date -u +%Y%m%dT%H%M%SZ)"
  log_info "moving the previous keystore to $backup"
  mv "$KEYSTORE_DIR" "$backup"
}

# ensure_identity: makes the volume hold the key from the keys Secret and prints its address.
ensure_identity() {
  local secret on_volume
  check_from_format
  secret=$(secret_address)
  log_info "key from .Values.key: $secret"
  check_from "$secret"
  on_volume=$(volume_addresses)

  if [[ -z "$on_volume" ]]; then
    log_info "volume holds no provider key yet"
    import_key
  elif [[ "$on_volume" == "$secret" ]]; then
    log_info "provider key already on the volume"
  elif [[ "${ALLOW_IDENTITY_CHANGE:-}" == "false" ]]; then
    fail "identity change blocked (.Values.allowIdentityChange=false)" \
      "the volume holds the key of $on_volume, .Values.key holds the key of $secret" \
      "restore .Values.key/.Values.keysecret of $on_volume, or set .Values.allowIdentityChange=true, or start with a new volume"
  else
    log_warn "provider identity changes on this volume"
    log_warn "  was: $on_volume (keystore moved to a backup directory)"
    log_warn "  now: $secret (from .Values.key)"
    log_warn "  the provider $on_volume stays registered on chain with its leases and certificate;"
    log_warn "  set .Values.allowIdentityChange=false to block this"
    move_keystore_aside "$on_volume"
    import_key
  fi
  echo "$secret"
}
