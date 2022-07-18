#!/bin/bash

if [[ $DEBUG == "true" ]]; then sleep 5000; fi

set -x

##
# Import key
##
cat "$AKASH_BOOT_KEYS/key-pass.txt" | { cat ; echo ; } | /bin/akash --home="$AKASH_HOME" keys import --keyring-backend="$AKASH_KEYRING_BACKEND"  "$AKASH_FROM" "$AKASH_BOOT_KEYS/key.txt"

##
# Check the Akash Node is working
##
apt update && apt -yqq install curl jq bc netcat
solo_ip=$(echo $AKASH_NODE | cut -d":" -f2 | cut -d "/" -f3) ; port=$(echo $AKASH_NODE | cut -d":" -f3-)
if [[ $AKASH_NODE != "http://akash-node-1:26657" ]]; then
  nc -z -v -w5 $solo_ip $port
fi
until [[ $(curl -s $AKASH_NODE/status | jq -r .result.sync_info.catching_up) == "false" ]]; do sleep 15; echo "Akash node not ready. Retrying";  done

# Check Akash RPC node isn't running behind too much and abort if it does.
DATE_AKASH=$(akash status | jq -r '.SyncInfo.latest_block_time')
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
EOT

# Figure the provider address in case the user passes `--from=<key_name>` instead of `--from=<akash1...>` address.
PROVIDER_ADDRESS="$(/bin/akash keys show $AKASH_FROM -a)"
if [[ -z "$PROVIDER_ADDRESS" ]]; then
  echo "PROVIDER_ADDRESS variable is empty. Something went wrong"
  exit 1
fi

/bin/akash query provider get $PROVIDER_ADDRESS -o json
if [[ $? -ne 0 ]]; then
  echo "Could not find provider: $PROVIDER_ADDRES on the blockchain when querying Akash RPC node: $AKASH_NODE"
  echo "Attempting to create a new provider ..."
  /bin/akash tx provider create provider.yaml >deploy.log 2>&1
  DEPLOY=$(cat deploy.log)
fi

if [[ $DEPLOY == *"incorrect account sequence"* ]]; then
  echo "Provider has issue talking to the node, check NODE is synced."
  exit 1
fi

if [[ $DEPLOY == *"already exists"* ]]; then
  echo "Provider already exists, continue..."
elif [[ $DEPLOY == *"Error"* ]]; then
  echo "Error creating provider : $DEPLOY"
  exit 1
fi

echo "Checking whether provider.yaml needs to be updated on the chain ..."
REMOTE_PROVIDER="$(akash query provider get $PROVIDER_ADDRESS -o json | jq | sha1sum | awk '{print $1}')"
LOCAL_PROVIDER="$(/bin/akash tx provider update provider.yaml --offline --generate-only --from $PROVIDER_ADDRESS | jq -r '.body.messages[]' | jq -r 'del(."@type")' | sha1sum | awk '{print $1}')"
if [[ "$REMOTE_PROVIDER" != "$LOCAL_PROVIDER" ]]; then
  echo "Updating provider in the blockchain ..."
  /bin/akash tx provider update provider.yaml >deploy.log 2>&1
  DEPLOY=$(cat deploy.log)

  if [[ $DEPLOY == *"insufficient fees"* ]]; then
    echo "Insufficient fees!  Change the fee settings."
    exit 1
  fi

  if [[ $DEPLOY == *"out of gas in location"* ]]; then
    echo "Out of gas!  Change gas/fee settings."
    exit 1
  fi

  if [[ $DEPLOY == *"incorrect account sequence"* ]]; then
    echo "Provider has issue talking to the node, check NODE is synced."
    exit 1
  fi

  if [[ $DEPLOY == *"Error"* ]]; then
    echo "Error creating provider : $DEPLOY"
    exit 1
  fi
fi

CERT_PATH="${AKASH_HOME}/${PROVIDER_ADDRESS}.pem"
# 0 = yes; otherwise do not (re-)generate new provider certificate, unless
GEN_NEW_CERT=1
LAST_CERT_STATUS="$(akash query cert list --owner $PROVIDER_ADDRESS --state valid -o json | jq -r '.certificates[-1].certificate.state')"
# Check whether the last broadcasted certificate is valid
if [[ "valid" != "$LAST_CERT_STATUS" ]]; then
  echo "No valid certificate found for provider: $PROVIDER_ADDRESS"
  GEN_NEW_CERT=0

  echo "It might as well be that the current certificate was expired, thus, it should be safe to delete it locally"
  # It's also a good idea to delete it as otherwise, we'd have to add `--overwrite` to `akash tx cert generate server` command later.
  if [[ -f "${CERT_PATH}" ]]; then
    rm -vf "${CERT_PATH}"
  fi
fi

# Check whether the local certificate matches the one on the blockchain
if [[ -f "${CERT_PATH}" ]]; then
  LOCAL_CERT_SN="$(cat "${CERT_PATH}" | openssl x509 -serial -noout)"
  REMOTE_CERT_SN="$(akash query cert list --owner $PROVIDER_ADDRESS --state valid | jq -r '.certificates[-1].certificate.cert' | openssl base64 -A -d | openssl x509 -serial -noout)"
else
  echo "${CERT_PATH} file is missing."
  GEN_NEW_CERT=0
fi
if [[ -z "$LOCAL_CERT_SN" ]]; then
  echo "LOCAL_CERT_SN variable is empty. Most likely ${CERT_PATH} file is empty or malformed."
  GEN_NEW_CERT=0
fi
if [[ -z "$REMOTE_CERT_SN" ]]; then
  echo "REMOTE_CERT_SN variable is empty. Most likely the cert hasn't been broadcasted to the blockchain yet."
  GEN_NEW_CERT=0
elif [[ "$LOCAL_CERT_SN" != "$REMOTE_CERT_SN" ]]; then
  echo "Local certificate SN does not match the one on the blockchain"
  GEN_NEW_CERT=0
fi

if [[ $GEN_NEW_CERT ]]; then
  echo "Generating new provider certificate"
  /bin/akash tx cert generate server provider.{{ .Values.domain }}
  echo "Publishing new provider certificate"
  /bin/akash tx cert publish server
fi
