# akash-provider

Helm chart for the Akash provider daemon (`provider-services run`). It runs as a StatefulSet with one
pod:

- **init container** (`init.sh`): sets up the `akt` context, checks the provider key, waits for the
  RPC node, creates or updates the provider record on chain and publishes the provider certificate;
- **main container** (`run.sh`): checks the key and certificate again, then starts the provider.

The provider's home (keystore, certificate, configuration) lives on a persistent volume.

Release notes: [CHANGELOG.md](CHANGELOG.md).

## Required values

| Parameter | Description |
|---|---|
| `from` | Provider address (or a key name). Checked against the key in `key`. |
| `key` | Provider private key, armored and base64-encoded. |
| `keysecret` | Passphrase of `key`, base64-encoded. |
| `domain` | Provider domain. The provider is reached at `provider.<domain>`, tenant hostnames are generated under `ingress.<domain>`. |
| `node` | RPC node (has a default, but set your own). |

## Parameters

"Environment variable" is the variable the setting is passed as; "–" means it is used by the chart
templates only. `(not set)` means the key is not in `values.yaml`; the variable is then left out.

### Provider identity and chain

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `from` | (not set, required) | `AKT_FROM`, `AKASH_FROM` | Provider address or key name. The address is always derived from `key`; a value that looks like an address but is not the key's address stops the provider at startup. |
| `key` | (not set, required) | – (Secret `<release>-keys`, mounted at `/boot-keys`) | Provider private key, armored, base64-encoded. |
| `keysecret` | (not set, required) | – (Secret `<release>-keys`, mounted at `/boot-keys`) | Passphrase of `key`, base64-encoded. |
| `allowIdentityChange` | `true` | `ALLOW_IDENTITY_CHANGE` | What to do when the volume already holds another account's key. `true`: start with the new key, with a warning; the previous keystore is moved to a backup directory on the volume. `false`: stop at startup with an error. |
| `chainid` | `akashnet-2` | `AKASH_CHAIN_ID` | Chain ID (`chain_id` in the network's `meta.json`). |
| `node` | `https://akash-rpc.polkachu.com:443` | `AKASH_NODE` | RPC node for the scripts and the provider. |
| `home` | `/root/.akash` | `AKT_HOME`, `AKASH_HOME` | Provider home on the volume: keystore, certificate, configuration. |
| `keyringbackend` | `test` | `AKT_KEYRING_BACKEND`, `AKASH_KEYRING_BACKEND` | Keystore backend. Only `test` is supported. |

### Provider record on chain

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `attributes` | (not set) | – | List of `key`/`value` attributes published in the provider record (region, host, storage classes, TEE platform, ...). See the commented example in `values.yaml`. A persistent storage class listed here is also used for the provider's volume (the last one, if several). |
| `email` | (not set) | – | Contact email in the provider record. Also used as the Let's Encrypt account email when `letsEncrypt.acme.email` is empty. |
| `website` | (not set) | – | Website in the provider record. |

### Transactions

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `gas` | `auto` | `AKT_GAS`, `AKASH_GAS` | Gas limit per transaction, or `auto` to estimate it. |
| `gasprices` | `0.025uakt` | `AKT_GAS_PRICES`, `AKASH_GAS_PRICES` | Gas price. The fee is gas × gas price. |
| `gasadjustment` | `1.5` | `AKT_GAS_ADJUSTMENT`, `AKASH_GAS_ADJUSTMENT` | Multiplier on the gas estimate (only with `gas: auto`). Increase it on "out of gas" errors. |
| `tx_broadcast_timeout` | `60s` | `AKASH_TX_BROADCAST_TIMEOUT` | How long the provider waits for its transaction to be included. |

### Bidding

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `bidpricecpuscale` | `0.004` | `AKASH_BID_PRICE_CPU_SCALE` | Price per CPU unit (scale pricing). |
| `bidpricememoryscale` | `0.0016` | `AKASH_BID_PRICE_MEMORY_SCALE` | Price per memory unit. |
| `bidpriceendpointscale` | `1` | `AKASH_BID_PRICE_ENDPOINT_SCALE` | Price per endpoint. |
| `bidpricestoragescale` | `0.00016,beta2=0.00016` | `AKASH_BID_PRICE_STORAGE_SCALE` | Price per storage unit; a default and per storage class (`<class>=<price>`). |
| `bidpriceipscale` | `60` | `AKASH_BID_PRICE_IP_SCALE` | Price per leased IP. |
| `bidmindeposit` | `500000uakt` | `AKASH_BID_DEPOSIT` | Deposit placed with each bid. |
| `overcommit_pct_cpu` | `0` | `AKASH_OVERCOMMIT_PCT_CPU` | Allowed CPU overcommit, %. |
| `overcommit_pct_mem` | `0` | `AKASH_OVERCOMMIT_PCT_MEM` | Allowed memory overcommit, %. |
| `overcommit_pct_storage` | `0` | `AKASH_OVERCOMMIT_PCT_STORAGE` | Allowed storage overcommit, %. |
| `bid_timeout` | (not set) | `AKASH_BID_TIMEOUT` | How long a bid may take. |
| `manifest_timeout` | (not set) | `AKASH_MANIFEST_TIMEOUT` | How long to wait for the tenant's manifest after a lease is created. |
| `authpem` | (not set) | `AKASH_AUTH_PEM` | Provider certificate as PEM, instead of the file on the volume. |

### Price script

Setting `bidpricescript` switches pricing from the scale factors above to the script
(`AKASH_BID_PRICE_STRATEGY: shellScript`). Sample scripts are in `scripts/`.

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `bidpricescript` | (not set) | `AKASH_BID_PRICE_STRATEGY`, `AKASH_BID_PRICE_SCRIPT_PATH` | Price script, base64-encoded: `--set bidpricescript="$(openssl base64 -A < price_script.sh)"`. |
| `whitelist_url` | (not set) | `WHITELIST_URL` | Tenant whitelist checked by the script. |
| `debug_bid_script` | (not set) | `DEBUG_BID_SCRIPT` | Debug output of the script. |
| `price_target_cpu` | (not set) | `PRICE_TARGET_CPU` | Target CPU price for the script. |
| `price_target_memory` | (not set) | `PRICE_TARGET_MEMORY` | Target memory price. |
| `price_target_hd_ephemeral` | (not set) | `PRICE_TARGET_HD_EPHEMERAL` | Target ephemeral storage price. |
| `price_target_hd_pers_hdd` | (not set) | `PRICE_TARGET_HD_PERS_HDD` | Target persistent HDD price. |
| `price_target_hd_pers_ssd` | (not set) | `PRICE_TARGET_HD_PERS_SSD` | Target persistent SSD price. |
| `price_target_hd_pers_nvme` | (not set) | `PRICE_TARGET_HD_PERS_NVME` | Target persistent NVMe price. |
| `price_target_endpoint` | (not set) | `PRICE_TARGET_ENDPOINT` | Target endpoint price. |
| `price_target_ip` | (not set) | `PRICE_TARGET_IP` | Target leased IP price. |
| `price_target_gpu_mappings` | (not set) | `PRICE_TARGET_GPU_MAPPINGS` | Target prices per GPU model. |

### Escrow and lease monitoring

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `withdrawalperiod` | `1h` | `AKASH_WITHDRAWAL_PERIOD` | How often lease earnings are withdrawn. |
| `reclamationWindow` | `""` | `AKASH_RECLAMATION_WINDOW` | Reclamation window offered to tenants (Go duration, e.g. `24h`). Empty: none. |
| `minimumbalance` | `10000000` | `AKASH_MINIMUM_BALANCE` | Minimum account balance (uakt) required to bid. |
| `lease_funds_monitor_interval` | (not set) | `AKASH_LEASE_FUNDS_MONITOR_INTERVAL` | How often lease funds are checked. |
| `monitor.maxRetries` | `2304` | `AKASH_MONITOR_MAX_RETRIES` | Failed status checks of a deployment before its lease is closed. Total retry time ≈ `maxRetries × (retryPeriod + retryPeriodJitter/2)`; the default is about 24 hours. |
| `monitor.retryPeriod` | `30s` | `AKASH_MONITOR_RETRY_PERIOD` | Time between status checks. |
| `monitor.retryPeriodJitter` | `15s` | `AKASH_MONITOR_RETRY_PERIOD_JITTER` | Random spread added to `retryPeriod`. |
| `monitor.healthcheckPeriod` | `10s` | `AKASH_MONITOR_HEALTHCHECK_PERIOD` | **No effect**: the provider does not read this variable. |
| `monitor.healthcheckPeriodJitter` | `5s` | `AKASH_MONITOR_HEALTHCHECK_PERIOD_JITTER` | **No effect**: the provider does not read this variable. |

### Cluster and deployments

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `domain` | (not set, required) | `AKASH_CLUSTER_PUBLIC_HOSTNAME` (`provider.<domain>`), `AKASH_DEPLOYMENT_INGRESS_DOMAIN` (`ingress.<domain>`) | Provider domain. Also used for the provider record (`https://provider.<domain>:8443`) and the provider certificate (`provider.<domain>`). |
| `cluster_node_port_quantity` | `2500` | `AKASH_CLUSTER_NODE_PORT_QUANTITY` | How many nodePorts the provider may hand out. |
| `ipoperator` | `false` | `AKASH_IP_OPERATOR` | Use the IP operator for leased IPs. |
| `deploymentnetworkpoliciesenabled` | `"true"` | `AKASH_DEPLOYMENT_NETWORK_POLICIES_ENABLED` | Network policies that isolate tenant namespaces. |

### Tenant traffic: Gateway API or Ingress

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `gatewayApi.enabled` | `true` | `AP_INGRESS_MODE` (`gateway-api` / `ingress`) | Route tenant traffic through Gateway API; `false` uses NGINX Ingress. The Gateway must exist before install. |
| `gatewayApi.gatewayName` | `akash-gateway` | `AP_GATEWAY_NAME` | Gateway the tenant routes (and the Let's Encrypt challenge route) attach to. |
| `gatewayApi.gatewayNamespace` | `akash-gateway` | `AP_GATEWAY_NAMESPACE` | Namespace of that Gateway; `""` means the release namespace. |
| `gatewayApi.implementation` | `nginx` | `AP_GATEWAY_IMPLEMENTATION` | **No effect**: the provider does not read this variable. |
| `ingress.className` | `akash-ingress-class` | – | Ingress class of the Let's Encrypt challenge Ingress (only with `gatewayApi.enabled: false`). |
| `ingress.annotations` | `{}` | – | **No effect**: not used by any template. |

### Let's Encrypt (TLS for tenant hostnames)

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `letsEncrypt.enabled` | `true` | `AP_CERT_ISSUER_ENABLED` | Provider gets TLS certificates for tenant hostnames. |
| `letsEncrypt.acme.email` | `""` | `AP_CERT_ISSUER_EMAIL` | ACME account email; empty uses `email`. |
| `letsEncrypt.acme.caDirUrl` | `https://acme-v02.api.letsencrypt.org/directory` | `AP_CERT_ISSUER_CA_DIR_URL` | ACME directory (use the staging URL for tests). |
| `letsEncrypt.acme.httpChallengePort` | `5002` | `AP_CERT_ISSUER_HTTP_CHALLENGE_PORT` | Port for HTTP-01 challenges; must match the Gateway / ingress side. |
| `letsEncrypt.providers.cloudflare.enabled` | `false` | `AP_CERT_ISSUER_DNS_PROVIDERS` (`cloudflare`) | Use Cloudflare for DNS-01 challenges. Takes precedence over Google Cloud. |
| `letsEncrypt.providers.cloudflare.apiToken` | `""` | `CF_DNS_API_TOKEN` (from Secret `<release>-cloudflare-dns`) | Cloudflare API token. |
| `letsEncrypt.providers.googleCloud.enabled` | `false` | `AP_CERT_ISSUER_DNS_PROVIDERS` (`googleCloud`), `GCE_SERVICE_ACCOUNT_FILE` | Use Google Cloud DNS for DNS-01 challenges. |
| `letsEncrypt.providers.googleCloud.serviceAccount.content` | `""` | – (Secret, mounted at `/etc/gcp/service-account.json`) | Google Cloud service account JSON. |
| `letsEncrypt.storage.storageClass` | `""` | – | Storage class of the provider's volume when `attributes` lists no persistent storage class. Empty: `<release>-local-storage` (local-path). |

### Confidential compute (TEE)

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `attestation.enabled` | `false` | `AKASH_ATTESTATION_WEBHOOK_ENABLED` | Inject the attestation sidecar into TEE workloads. Also needs TEE attributes in `attributes`. |
| `attestation.webhookEnabled` | `false` | `AKASH_ATTESTATION_WEBHOOK_ENABLED` | Alias of `attestation.enabled`. |
| `attestation.webhookPort` | `9443` | `AKASH_ATTESTATION_WEBHOOK_PORT` | Port of the sidecar webhook. |
| `attestation.sidecarImage.repository` | `ghcr.io/akash-network/provider-attestation-sidecar` | `AKASH_ATTESTATION_SIDECAR_IMAGE` | Sidecar image. |
| `attestation.sidecarImage.tag` | `""` | `AKASH_ATTESTATION_SIDECAR_IMAGE` | Sidecar image tag; empty uses the chart's appVersion. |

### Logging

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `logging.level` | `info` | `AP_LOG_LEVEL` | `trace`, `debug`, `info`, `warn`, `error`, `fatal`, `panic`, or a per-module filter, e.g. `bidengine-order:debug,*:info`. |
| `logging.format` | `json` | `AP_LOG_FORMAT` | `json` or `plain`. |
| `logging.color` | `false` | `AP_LOG_COLOR` | ANSI colors (plain format only). |
| `logging.timestamp` | `rfc3339` | `AP_LOG_TIMESTAMP` | `"off"`, `rfc3339`, `rfc3339nano`, `kitchen`. Quote `"off"`. |
| `logging.trace` | `false` | `AP_TRACE` | Stack traces on error entries. |

### Debug

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `debug` | `"false"` | `AKASH_DEBUG` | Start the provider under the dlv debugger. |

### Kubernetes

| Parameter | Default | Environment variable | Description |
|---|---|---|---|
| `image.repository` | `ghcr.io/akash-network/provider` | – | Provider image. |
| `image.tag` | (not set) | – | Image tag; empty uses the chart's appVersion. |
| `image.pullPolicy` | `IfNotPresent` | – | Image pull policy. |
| `imagePullSecrets` | `[]` | – | Image pull secrets. |
| `nameOverride` | `""` | – | Overrides the chart name in resource names. |
| `fullnameOverride` | `""` | – | Overrides the full resource name prefix. |
| `serviceAccount.create` | `true` | – | Create a service account. |
| `serviceAccount.annotations` | `{}` | – | Service account annotations. |
| `serviceAccount.name` | (not set) | – | Service account name; empty uses the generated name. |
| `podSecurityContext` | `{}` | – | Pod security context. |
| `securityContext` | `{}` | – | Container security context. |
| `resources` | limits `2000m` / `4096Mi`, requests `1000m` / `2048Mi` | – | Provider container resources. |
| `nodeSelector` | `{}` | – | Node selector. |
| `tolerations` | `[]` | – | Tolerations. |
| `affinity` | `{}` | – | Affinity. |
| `storage.home.size` | `10Gi` | – | Size of the provider's volume. |
| `storage.home.accessMode` | `ReadWriteOnce` | – | Access mode of the provider's volume. |
| `autoscaling.*` | `enabled: false`, ... | – | **No effect**: not used by any template (the provider runs as a single StatefulSet pod). |

## Fixed environment variables

Set by the chart, not configurable.

| Environment variable | Value | Why fixed |
|---|---|---|
| `AKASH_BOOT_KEYS` | `/boot-keys` | Mount path of the keys Secret. |
| `AKT_BROADCAST_MODE`, `AKASH_BROADCAST_MODE` | `block` | Wait for each transaction to be included; the scripts read its result. |
| `AKASH_YES` | `true` | The provider must not ask for confirmation on stdin. |
| `AKASH_CLUSTER_K8S` | `true` | The provider runs against Kubernetes. |
| `AKASH_DEPLOYMENT_INGRESS_STATIC_HOSTS` | `true` | Every HTTP service gets a generated `<uid>.ingress.<domain>` hostname. |
| `AKASH_DEPLOYMENT_BLOCKED_HOSTNAMES` | `""` | No hostnames blocked for tenants. |
| `AKASH_DEPLOYMENT_RUNTIME_CLASS` | `none` | No runtime class for tenant pods (the provider sets `nvidia` for GPU and `kata-qemu-*` for TEE workloads itself). |
