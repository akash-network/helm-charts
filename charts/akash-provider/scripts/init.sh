#!/bin/bash

if [[ $AKASH_DEBUG == "true" ]]; then sleep 5000; fi

set -x

##
# Import key
##
cat "$AKASH_BOOT_KEYS/key-pass.txt" | { cat ; echo ; } | provider-services --home="$AKASH_HOME" keys import --keyring-backend="$AKASH_KEYRING_BACKEND"  "$AKASH_FROM" "$AKASH_BOOT_KEYS/key.txt"

##
# Check the Akash Node is working
##
apt update && apt -yqq install curl jq bc netcat ca-certificates

# fail fast should there be a problem installing curl, jq, nc packages
type curl || exit 1
type jq || exit 1
type nc || exit 1

solo_ip=$(echo $AKASH_NODE | cut -d":" -f2 | cut -d"/" -f3)
port=$(echo $AKASH_NODE | cut -d":" -f3 | cut -d"/" -f1)
if [[ $AKASH_NODE != "http://akash-node-1:26657" ]]; then
  nc -z -v -w5 $solo_ip $port
fi
until [[ $(curl -s $AKASH_NODE/status | jq -r .result.sync_info.catching_up) == "false" ]]; do sleep 15; echo "Akash node not ready. Retrying";  done

# Check Akash RPC node isn't running behind too much and abort if it does.
DATE_AKASH=$(curl -s $AKASH_NODE/status | jq -r '.result.sync_info.latest_block_time')
TS_AKASH=$(date +%s --date "$DATE_AKASH")
TS=$(date +%s)
DIFF=$(echo "$TS - $TS_AKASH" | bc)
if [[ "$DIFF" -gt 30 ]]; then
  echo "Akash RPC $AKASH_NODE is running $DIFF seconds behind."
  echo "ACTION: Make sure your system time in synchronized and/or check your Akash RPC node."
  exit 1
elif [[ "$DIFF" -lt -30 ]]; then
  echo "Akash RPC $AKASH_NODE is running $DIFF seconds ahead."
  echo "ACTION: Make sure your system time in synchronized and/or check your Akash RPC node."
  exit 1
else
  echo "Last block Akash RPC $AKASH_NODE seen was $DIFF seconds ago => OK"
fi

##
# Create Provider
##

cat <<EOT > provider.yaml
host: https://provider.{{ .Values.domain }}:8443
attributes:
{{- range $key, $val := .Values.attributes }}
  - key: {{ $val.key }}
    value: {{ $val.value }}
{{- end }}
info:
  email: {{ .Values.email }}
  website: {{ .Values.website }}
owner: {{ .Values.from }}
EOT

# Figure the provider address in case the user passes `--from=<key_name>` instead of `--from=<akash1...>` address.
PROVIDER_ADDRESS="$(provider-services keys show $AKASH_FROM -a)"
if [[ -z "$PROVIDER_ADDRESS" ]]; then
  echo "PROVIDER_ADDRESS variable is empty. Something went wrong"
  exit 1
fi

provider-services query provider get $PROVIDER_ADDRESS -o json
if [[ $? -ne 0 ]]; then
  echo "Could not find provider: $PROVIDER_ADDRES on the blockchain when querying Akash RPC node: $AKASH_NODE"
  echo "Attempting to create a new provider ..."
  provider-services tx provider create provider.yaml
fi

echo "Checking whether provider.yaml needs to be updated on the chain ..."
diff --color -Nur <(cat provider.yaml | awk '/attributes:/{print;flag=1;next}/^  - key:/{if(flag)sub("  ","");print;next}flag&&/^    /{sub("    ","  ");print;next}{flag=0;print}' | sort) <(provider-services query provider get $PROVIDER_ADDRESS -o text | sed -e 's/"//g' -e 's/host_uri:/host:/g' | sort)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Updating provider info in the blockchain in 10 seconds ..."
  sleep 10s
  echo provider-services tx provider update provider.yaml
fi

CERT_SYMLINK="${AKASH_HOME}/${PROVIDER_ADDRESS}.pem"
CERT_REAL_PATH="/config/provider.pem"
rm -vf "$CERT_SYMLINK"
# provider cert is coming from the configmap
ln -sv "$CERT_REAL_PATH" "$CERT_SYMLINK"
# 0 = yes; otherwise do not (re-)generate new provider certificate, unless
GEN_NEW_CERT=1

# Check whether the certificate is present and valid on the blockchain
if [[ -f "${CERT_REAL_PATH}" ]]; then
  LOCAL_CERT_SN="$(cat "${CERT_REAL_PATH}" | openssl x509 -serial -noout | cut -d'=' -f2)"
  LOCAL_CERT_SN_DECIMAL=$(echo "obase=10; ibase=16; $LOCAL_CERT_SN" | bc)
  REMOTE_CERT_STATUS="$(AKASH_OUTPUT=json provider-services query cert list --owner $PROVIDER_ADDRESS --state valid --serial $LOCAL_CERT_SN_DECIMAL --reverse | jq -r '.certificates[0].certificate.state')"
  echo "Provider certificate serial number: ${LOCAL_CERT_SN:-unknown}, status on chain: ${REMOTE_CERT_STATUS:-unknown}"
else
  echo "${CERT_REAL_PATH} file is missing."
  GEN_NEW_CERT=0
fi

if [[ -z "$LOCAL_CERT_SN" ]]; then
  echo "LOCAL_CERT_SN variable is empty. Most likely ${CERT_REAL_PATH} file is empty or malformed."
  GEN_NEW_CERT=0
fi

if [[ "valid" != "$REMOTE_CERT_STATUS" ]]; then
  echo "No valid certificate found for provider: $PROVIDER_ADDRESS"
  GEN_NEW_CERT=0

  echo "It might as well be that the current certificate was expired/revoked, thus, it should be safe to delete it locally"
fi

# generate a new cert if the current one expires sooner than 7 days
AKASH_OUTPUT=json provider-services query cert list --owner $PROVIDER_ADDRESS --state valid --reverse | jq -r '.certificates[0].certificate.cert' | openssl base64 -A -d | openssl x509 -checkend 604800 -noout 2>/dev/null 1>&2
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Certificate expires in less than 7 days, so going to generate a new one."
  GEN_NEW_CERT=0
fi

# check if current local cert has expired
# TODO: should probably add a healthCheck which would keep doing this every 5 minutes to bounce the pod if cert got expired
openssl x509 -checkend 604800 -noout -in "${CERT_REAL_PATH}" 2>/dev/null 1>&2
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Certificate expires in less than 7 days, so going to generate a new one."
  GEN_NEW_CERT=0
fi

if [[ "$GEN_NEW_CERT" -eq "0" ]]; then
  echo "Removing the old certificate before generating a new one"
  # It's also a good idea to delete it as otherwise, we'd have to add `--overwrite` to `provider-services tx cert generate server` command later.
  rm -vf "${CERT_REAL_PATH}"

  echo "Generating new provider certificate"
  provider-services tx cert generate server provider.{{ .Values.domain }}

  echo "Publishing new provider certificate"
  provider-services tx cert publish server
fi
