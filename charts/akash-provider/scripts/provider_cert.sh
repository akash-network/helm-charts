#!/bin/bash
# Filename: provider_cert.sh
#
# The provider certificate: kept when valid, otherwise generated and published on chain.
# Sourced by init.sh and run.sh (ensure_cert <address>).
#
# The certificate lives on the node (hostPath /config/provider.pem); $AKT_HOME/<address>.pem, where
# akt and the daemon expect it, is a link to that file.

source /scripts/lib.sh

CERT_FILE=/config/provider.pem
CERT_DOMAIN="provider.{{ .Values.domain }}"

# cert_serial: serial of the local certificate, in decimal (as the chain lists it).
cert_serial() {
  echo "obase=10; ibase=16; $(openssl x509 -noout -serial -in "$CERT_FILE" | cut -d= -f2)" | BC_LINE_LENGTH=0 bc
}

# cert_state <address>: prints one of
#   ok <serial> <expiry> | missing | unreadable | other-owner <owner> | not-on-chain <serial> | expiring <expiry>
cert_state() {
  local address=$1 owner serial expiry json
  if [[ ! -s "$CERT_FILE" ]]; then echo "missing"; return; fi
  if ! openssl x509 -noout -in "$CERT_FILE" >/dev/null 2>&1; then echo "unreadable"; return; fi

  owner=$(openssl x509 -noout -subject -nameopt multiline -in "$CERT_FILE" | sed -n 's/^ *commonName *= *//p')
  if [[ "$owner" != "$address" ]]; then echo "other-owner $owner"; return; fi

  serial=$(cert_serial)
  json=$(chain_query akt query cert list "$address" valid --serial "$serial" -o json)
  if [[ "$(jq '.certificates | length' <<<"$json")" == "0" ]]; then echo "not-on-chain $serial"; return; fi

  expiry=$(date -u -d "$(openssl x509 -noout -enddate -in "$CERT_FILE" | cut -d= -f2)" +%Y-%m-%d)
  if ! openssl x509 -checkend 604800 -noout -in "$CERT_FILE" >/dev/null; then echo "expiring $expiry"; return; fi
  echo "ok $serial $expiry"
}

# ensure_cert <address>: links $AKT_HOME/<address>.pem to the certificate file, keeps the certificate
# when it is valid, otherwise logs the reason, generates a new one and publishes it on chain.
ensure_cert() {
  local address=$1 out state detail extra reason
  ln -sfn "$CERT_FILE" "$AKT_HOME/$address.pem"

  out=$(cert_state "$address")
  read -r state detail extra <<<"$out"
  case $state in
    ok)
      log_info "provider certificate valid until $extra (serial $detail)"
      return
      ;;
    missing)      reason="no certificate file ($CERT_FILE)" ;;
    unreadable)   reason="certificate file is not a valid certificate" ;;
    other-owner)  reason="certificate belongs to $detail, not to $address" ;;
    not-on-chain) reason="certificate serial $detail is not valid on chain (revoked or never published)" ;;
    expiring)     reason="certificate expires within 7 days ($detail)" ;;
    *)            exit 1 ;;
  esac

  log_info "new provider certificate needed: $reason"
  rm -f "$CERT_FILE"
  run akt tx cert generate server "$CERT_DOMAIN" --from "$address" >/dev/null
  send_tx akt tx cert publish server --from "$address" -y
  log_info "provider certificate published (serial $(cert_serial))"
}
