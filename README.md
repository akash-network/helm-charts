## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```
helm repo add akash https://ovrclk.github.io/helm-charts
```

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages. You can then run `helm search repo akash` to see the charts.

### Example

To install the provider chart make sure you have your [provider-cert.pem](https://docs.akash.network/operations/provider#creating-the-provider-on-the-blockchain) in the current directory and then set the env vars below and install the chart.

```
akash_key=<AkashPublicAddress>
akash_password=<mypassword>
helm install provider akash/provider --set akash_provider.key=$akash_key --set akash_provider.keysecret=$akash_password --set-file akash_provider.providercert=provider-cert.pem
```

To uninstall the chart:

```
helm delete provider
```
