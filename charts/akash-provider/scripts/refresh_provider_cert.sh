#!/bin/bash
# Filename: refresh_provider_cert.sh

set -x

# Figure the provider address in case the user passes `--from=<key_name>` instead of `--from=<akash1...>` address.
PROVIDER_ADDRESS="$(provider-services keys show $AKASH_FROM -a)"
if [[ -z "$PROVIDER_ADDRESS" ]]; then
  echo "PROVIDER_ADDRESS variable is empty. Something went wrong"
  exit 1
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
