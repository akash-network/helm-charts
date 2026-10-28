#!/bin/bash
# Filename: provider_record.sh
#
# The provider record on chain: created when missing, updated when it differs from the values.
# Sourced by init.sh (ensure_provider <address>).

source /scripts/lib.sh

PROVIDER_FILE=/tmp/provider.yaml

# write_provider_file: writes the provider config from the chart values to $PROVIDER_FILE, as JSON
# (valid YAML for `akt tx provider`). Every value is a string, as on chain. Helm renders the heredoc
# body to a single JSON line.
write_provider_file() {
  cat <<'EOT' > "$PROVIDER_FILE"
{{- $attributes := list }}
{{- range .Values.attributes }}
{{- $attributes = append $attributes (dict "key" (toString .key) "value" (toString .value)) }}
{{- end }}
{{- $info := dict "email" (toString (.Values.email | default "")) "website" (toString (.Values.website | default "")) }}
{{- $provider := dict "host" (printf "https://provider.%s:8443" .Values.domain) "attributes" $attributes "info" $info }}
{{ $provider | toJson }}
EOT
}

# desired_provider: prints the fields that are compared with the chain, taken from $PROVIDER_FILE:
# host, attributes (sorted, compared as a set), email, website.
desired_provider() {
  jq -S '{host_uri: .host, attributes: (.attributes | sort_by(.key, .value)), info: {email: .info.email, website: .info.website}}' "$PROVIDER_FILE"
}

# chain_fields: reads the JSON of `akt query provider get` on stdin and prints the same fields as
# desired_provider, so the two can be compared as text. Missing fields become empty.
chain_fields() {
  jq -S '.provider | {host_uri, attributes: ((.attributes // []) | sort_by(.key, .value)), info: {email: (.info.email // ""), website: (.info.website // "")}}'
}

# ensure_provider <address>: creates the provider record on chain if it is missing, updates it if its
# fields differ from the values, otherwise does nothing. Logs which of the three happened.
ensure_provider() {
  local address=$1 json rc want have
  write_provider_file
  want=$(desired_provider)

  if json=$(chain_query akt query provider get "$address" -o json); then rc=0; else rc=$?; fi
  case $rc in
    0) ;;
    3)
      log_info "provider $address not on chain: creating it"
      send_tx akt tx provider create "$PROVIDER_FILE" --from "$address" -y
      return
      ;;
    *) exit 1 ;;
  esac

  have=$(chain_fields <<<"$json")
  if [[ "$want" == "$have" ]]; then
    log_info "provider on chain, up to date"
    return
  fi
  log_info "provider on chain differs from the values: updating it"
  diff <(echo "$have") <(echo "$want") | sed -n 's/^[<>]/  &/p' >&2 || true
  send_tx akt tx provider update "$PROVIDER_FILE" --from "$address" -y
}
