#!/bin/bash
# Filename: create_provider.sh

set -x

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

##
# Update Provider
##

echo "Checking whether provider.yaml needs to be updated on the chain ..."
diff --color -Nur <(cat provider.yaml | awk '/attributes:/{print;flag=1;next}/^  - key:/{if(flag)sub("  ","");print;next}flag&&/^    /{sub("    ","  ");print;next}{flag=0;print}' | sort) <(provider-services query provider get $PROVIDER_ADDRESS -o text | sed -e 's/"//g' -e 's/host_uri:/host:/g' | sort)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Updating provider info in the blockchain in 10 seconds ..."
  sleep 10s
  provider-services tx provider update provider.yaml
fi
