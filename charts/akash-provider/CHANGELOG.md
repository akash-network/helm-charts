# akash-provider chart: release notes

## 19.1.0 (provider 0.16.5)

Also in this release: `akash-inventory-operator`, `akash-hostname-operator` and `akash-ip-operator`
19.1.0 (provider 0.16.5, new `logging` settings), `akash-node` 18.1.0.

Upgrading from 19.0.x? Read **Breaking and potentially breaking changes** and **Before you upgrade**
first.

### Highlights

- **The chart's startup scripts use the `akt` CLI** (bundled in the provider image since 0.16.5) for
  keys, chain queries and transactions. The provider itself (`provider-services run`) is unchanged.
- **Clear startup logs.** Each step prints what it checked and what it decided. Errors say what is
  wrong, what was found and how to fix it, and stop the provider instead of being ignored.
- **New option `allowIdentityChange`.** Set it to `false` to block the provider from starting when
  `key` / `keysecret` belong to a different account than the one already set up on the provider's
  volume.
- **New `logging` settings** in the provider, inventory, hostname and ip operator charts:
  `logging.level`, `logging.format` (default `json`), `logging.color`, `logging.timestamp`,
  `logging.trace`.
- **The chart installs again with Let's Encrypt off.** Let's Encrypt is on by default
  (`letsEncrypt.enabled: true`, unchanged). With `letsEncrypt.enabled: false`, charts 15.1.0-rc0 to
  19.0.x failed to install: Kubernetes rejected the provider StatefulSet.

### Breaking and potentially breaking changes

| # | What changes | Who is affected | What to do |
|---|---|---|---|
| 1 | **A wrong `keysecret` (or an unreadable `key`) now stops the provider at startup**, even when the key is already on the volume. Before, the Secret was not checked once the key was on the volume. | Providers whose `keysecret` no longer matches `key` | Make sure `key` and `keysecret` are correct before upgrading. |
| 2 | **`from` that looks like an address but is not the address of `key` now stops the provider at startup**, with both addresses in the error. Before, a different valid address made the provider crash later, and a mistyped address was silently used as a key name. | Providers with a wrong or mistyped address in `from` | Set `from` to the provider address (or to a plain key name). |
| 3 | **Changing only `key` now has an effect.** Before, a different key in `key` was ignored once a key was on the volume. Now: with `from` still set to the old address, the provider stops with an error; with `from` set to a key name, the provider switches to the new key (see 4). | Providers that changed `key` without changing `from` | Keep `key`/`keysecret` and `from` consistent. |
| 4 | **Switching to another account on an existing volume** (new `from` + new `key`) still works by default, but is now logged as a warning naming both accounts, and the previous account's keys are moved to a backup directory on the volume. With `allowIdentityChange: false` the provider refuses to start instead. The previous provider stays registered on chain with its leases (unchanged). | Providers that change their account | Nothing, unless you want to block this: set `allowIdentityChange: false`. |
| 5 | **`bid_timeout`, `manifest_timeout`, `lease_funds_monitor_interval` and `authpem` now apply whenever set.** Before, they applied only if a price-script setting (`bidpricescript`, `whitelist_url`, `price_target_*`, ...) was also set. | Providers that set these values | Check that the values are what you want. |
| 6 | **Undocumented settings that had no effect are no longer read**, e.g. `bid_deposit`, `withdrawal_period`, `deployment_runtime_class`. None of them changed what the provider did in 19.0.x. See **Removed chart settings**. | Providers that set any of them | Use the setting in the "Use instead" column, where there is one. |
| 7 | **Default log format is `json`** in the provider and the inventory, hostname and ip operators (19.0.x logged plain text). | Anyone parsing provider or operator logs | Set `logging.format: plain` to keep plain text. |
| 8 | **Environment variables removed or renamed.** See **Removed environment variables**. | Custom price scripts or tooling that read these variables | Check your price script; the `PRICE_TARGET_*`, `WHITELIST_URL` and `DEBUG_BID_SCRIPT` variables are unchanged. |
| 9 | **ConfigMaps `<release>-pricing` and `<release>-letsencrypt` are gone**; their settings are in `<release>-main`. | Tooling that reads these ConfigMaps by name | Read `<release>-main`. |

### Removed chart settings

Their values never reached the provider in 19.0.x, and no chart script reads them (19.0.x or 19.1.0), so
removing them changes nothing. Six of them were in `values.yaml`: `autoscaling.*` and `ingress.annotations`,
which no template used; the two `monitor.healthcheckPeriod*` settings, whose flags the provider itself
removed; and two that are replaced by new settings (see Other changes): `deploymentnetworkpoliciesenabled`
by `deploymentNetworkPoliciesEnabled`, and `gatewayApi.implementation` by `gatewayApi.gatewayProvider`.

| Removed setting | Variable it set in 19.0.x | Used by the provider? | Used by chart scripts? | Use instead |
|---|---|---|---|---|
| `bid_deposit` | `AKASH_BID_DEPOSIT` | No: the variable was always overridden by `bidmindeposit` | No | `bidmindeposit` |
| `withdrawal_period` | `AKASH_WITHDRAWAL_PERIOD` | No: the variable was always overridden by `withdrawalperiod` | No | `withdrawalperiod` |
| `deployment_runtime_class` | `AKASH_DEPLOYMENT_RUNTIME_CLASS` | No: the variable was always overridden by `none`, and the provider ignores this setting anyway (GPU workloads get the `nvidia` runtime class automatically) | No | – |
| `bid_price_cpu` | `AKASH_BID_PRICE_CPU` | No: no such provider setting | No | `bidpricecpuscale` |
| `bid_price_memory` | `AKASH_BID_PRICE_MEMORY` | No: no such provider setting | No | `bidpricememoryscale` |
| `bid_price_storage` | `AKASH_BID_PRICE_STORAGE` | No: no such provider setting | No | `bidpricestoragescale` |
| `biddepositcpudenom` | `AKASH_BID_DEPOSIT_CPU_DENOM` | No: no such provider setting | No | – |
| `biddepositmemorydenom` | `AKASH_BID_DEPOSIT_MEMORY_DENOM` | No: no such provider setting | No | – |
| `biddepositendpointdenom` | `AKASH_BID_DEPOSIT_ENDPOINT_DENOM` | No: no such provider setting | No | – |
| `biddepositipdenom` | `AKASH_BID_DEPOSIT_IP_DENOM` | No: no such provider setting | No | – |
| `biddepositstoragedenoms` | `AKASH_BID_DEPOSIT_STORAGE_DENOMS` | No: no such provider setting | No | – |
| `balances_period` | `AKASH_BALANCES_PERIOD` | No: no such provider setting | No | – |
| `cluster_storage_class` | `AKASH_CLUSTER_STORAGE` | No: no such provider setting | No | storage classes: `inventoryConfig.cluster_storage` in `akash-inventory-operator` |
| `deployment_ingress_domain_config_secret_name` | `AKASH_DEPLOYMENT_INGRESS_DOMAIN_CONFIG_SECRET_NAME` | No: no such provider setting | No | – |
| `resourcedefinition` | `AKASH_RESOURCE_DEFINITION` | No: no such provider setting | No | – |
| `query_timeout` | `AKASH_QUERY_TIMEOUT` | No: it is a setting of the inventory operator, which runs in its own pod | No | – |
| `deploymentnetworkpoliciesenabled` | `DEPLOYMENT_NETWORK_POLICIES_ENABLED` | No: the provider reads `AKASH_DEPLOYMENT_NETWORK_POLICIES_ENABLED`; tenant network policies were always on | No | `deploymentNetworkPoliciesEnabled` (default `true`) |
| `gatewayApi.implementation` | `AP_GATEWAY_IMPLEMENTATION` | No: wrong variable name; the provider reads `AP_GATEWAY_PROVIDER` | No | `gatewayApi.gatewayProvider` |
| `monitor.healthcheckPeriod` | `AKASH_MONITOR_HEALTHCHECK_PERIOD` | No: removed from the provider in 0.16.0 (provider #418): periodic health checks after a deployment is up are off, because they could close stable leases | No | – |
| `monitor.healthcheckPeriodJitter` | `AKASH_MONITOR_HEALTHCHECK_PERIOD_JITTER` | No: same | No | – |
| `autoscaling.*` | – (chart setting only) | No: not used by any template since chart 4.0.5 (2022-11-21), when the provider moved to a StatefulSet with one pod; a provider must run as exactly one pod | No | – |
| `ingress.annotations` | – (chart setting only) | No: never used since it was added in chart 12.1.3 (2025-10-07) | No | – |

### Removed environment variables

Compared with 19.0.x, with all optional settings enabled. Variables kept under the same name are not
listed.

**Init container.** Its scripts now use `akt` instead of `provider-services`.

| Removed variable | Replaced by | Note |
|---|---|---|
| `AKASH_HOME` | `AKT_HOME` | same value (`home`) |
| `AKASH_FROM` | `AKT_FROM` | same value (`from`) |
| `AKASH_KEYRING_BACKEND` | `AKT_KEYRING_BACKEND` | same value (`keyringbackend`) |
| `AKASH_GAS` | `AKT_GAS` | same value (`gas`) |
| `AKASH_GAS_PRICES` | `AKT_GAS_PRICES` | same value (`gasprices`) |
| `AKASH_GAS_ADJUSTMENT` | `AKT_GAS_ADJUSTMENT` | same value (`gasadjustment`) |
| `AKASH_BROADCAST_MODE` | `AKT_BROADCAST_MODE` | same value (`block`) |
| `AKASH_YES`, `AP_YES` | – | `akt` gets `-y` on each transaction |
| `AP_MINIMUM_GAS_PRICES` | – | only used by a blockchain node, never by these scripts |
| `AKASH_LOG_LEVEL` | – | no longer used by the init scripts |
| `AKASH_DEBUG` | – | only used by the main container (`run.sh`) |

**Main container.**

| Removed variable | Replaced by | Note |
|---|---|---|
| `DEPLOYMENT_NETWORK_POLICIES_ENABLED` | `AKASH_DEPLOYMENT_NETWORK_POLICIES_ENABLED` | the old name was never read; now from `deploymentNetworkPoliciesEnabled` (default `true`) |
| `AP_GATEWAY_IMPLEMENTATION` | `AP_GATEWAY_PROVIDER` | the old name was never read; now from `gatewayApi.gatewayProvider` (default `nginx`) |
| `AKASH_MONITOR_HEALTHCHECK_PERIOD`, `AKASH_MONITOR_HEALTHCHECK_PERIOD_JITTER` | – | no such provider setting since 0.16.0 (health checks after start removed) |
| `AKASH_LOG_LEVEL` | `AP_LOG_LEVEL` | from `logging.level` (default `info`, as before) |
| `AKASH_BOOT_KEYS` | – | only used by the init container |
| `AKASH_VERSION` | – | no such provider setting |
| `KUBE_CONFIG` | – | wrong name; the provider reads `KUBECONFIG` |
| `AP_MINIMUM_GAS_PRICES` | – | only used by a blockchain node, not by the provider |
| `AKASH_BALANCES_PERIOD`, `AKASH_BID_PRICE_CPU`, `AKASH_BID_PRICE_MEMORY`, `AKASH_BID_PRICE_STORAGE`, `AKASH_BID_DEPOSIT_CPU_DENOM`, `AKASH_BID_DEPOSIT_MEMORY_DENOM`, `AKASH_BID_DEPOSIT_ENDPOINT_DENOM`, `AKASH_BID_DEPOSIT_IP_DENOM`, `AKASH_BID_DEPOSIT_STORAGE_DENOMS`, `AKASH_CLUSTER_STORAGE`, `AKASH_DEPLOYMENT_INGRESS_DOMAIN_CONFIG_SECRET_NAME`, `AKASH_RESOURCE_DEFINITION`, `AKASH_QUERY_TIMEOUT` | – | set by the removed settings above; not read by the provider |

New in the main container: the `AKT_*` variables (as in the init container) and `AP_LOG_FORMAT`,
`AP_LOG_COLOR`, `AP_LOG_TIMESTAMP`, `AP_TRACE` (from `logging.*`).

### Other changes

- **Tenant network policies: new setting `deploymentNetworkPoliciesEnabled`** (default `true`). It
  replaces `deploymentnetworkpoliciesenabled`, which 19.0.x never applied: tenant network policies were
  always on, whatever its value (default `"false"`). The old setting is now ignored. Design decision:
  no hidden breaking change. Honoring the old setting would have silently turned tenant network
  policies off for every provider whose values still carry the old `"false"`. Policies stay on after
  the upgrade; to turn them off, set `deploymentNetworkPoliciesEnabled: false`.
- **Gateway provider setting now applied: `gatewayApi.gatewayProvider`** (default `nginx`), in the provider
  and hostname operator charts. It replaces `gatewayApi.implementation`, which was passed as
  `AP_GATEWAY_IMPLEMENTATION`: the provider renamed that flag to `--gateway-provider` before its first
  Gateway API release (0.12.0), so the setting never had an effect. The old setting is ignored, so nothing
  changes on upgrade. Only `nginx` is supported; another value stops the provider and the hostname
  operator at startup in Gateway API mode.
- **No more extra on-chain update on every start** when `from` is a key name instead of an address.
  Before, such providers paid for a provider update that changed nothing on every restart.
- **Attribute changes apply faster**: the 10-second pause before a provider update is gone.
- **Chain errors no longer trigger transactions.** A failing RPC node is reported as an error and
  retried; it is never mistaken for "provider not registered".
- **The wait for the RPC node is limited to 10 minutes**, then the provider stops with a clear error.
  Before, it waited forever.
- **Changes to the provider's settings now restart the provider pod** (the env ConfigMaps are part of
  the pod's checksum). Before, some changes needed a manual restart.
- **Endpoint bid price typo fixed.** A typo in the chart left `AKASH_BID_PRICE_ENDPOINT_SCALE` empty
  (endpoint price 0) in charts 11.6.4 to 11.x, and in 12.0.0 to 15.0.x with Let's Encrypt off. 19.0.x is
  not affected: with Let's Encrypt on, the correct value was set elsewhere, and with it off the chart
  did not install. 19.1.0 sets it from `bidpriceendpointscale` in every case.
- **`akash-node`**: new `localnet` setting to run a single-validator local chain, for testing. Off by
  default; with default settings the chart renders exactly as 18.0.0.

### Before you upgrade

1. Check that `key` and `keysecret` are correct (change 1).
2. Check that `from` is the provider's address or a plain key name (change 2).
3. If you want the provider to refuse to start with another account's key, set
   `allowIdentityChange: false`.

If the provider pod is already crash-looping, a corrected `helm upgrade` is not applied to it
automatically (Kubernetes does not replace a pod that is not Ready); delete the pod once after the
upgrade: `kubectl -n akash-services delete pod akash-provider-0`.
