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

To install the provider chart make sure you have the following setup:

- Place a [provider-cert.pem](https://docs.akash.network/operations/provider#creating-the-provider-on-the-blockchain) in the current directory
- Place your private key in a file named `key.pem` in the current directory
- Set the `AKASH_KEY_NAME` and `AKASH_PASSWORD` env vars
- Install the [Akash network CRD](https://github.com/ovrclk/akash/blob/master/pkg/apis/akash.network/v1/crd.yaml)
- Install the [Provider host CRD](https://github.com/ovrclk/akash/blob/troian/storage/pkg/apis/akash.network/v1/provider_hosts_crd.yaml)

```
export AKASH_KEY_NAME=<mykeyname>
export AKASH_PASSWORD=<mykeypassword>
export AKASH_ACCOUNT_ADDRESS="$(akash keys show $AKASH_KEY_NAME -a)"

helm install provider akash/provider --set akash_client.from=$AKASH_ACCOUNT_ADDRESS --set akash_client.keysecret="$(echo $AKASH_PASSWORD | base64)" --set akash_client.key="$(cat ./key.pem | base64)" --set akash_provider.providercert="$(cat ./provider-cert.pem | base64)"
```

To uninstall the chart:

```
helm delete provider
```

### Connecting to a Testnet

As an example we used the following config to connect to the Akash testnet-1.

We set our environment variables for `$AKASH_ACCOUNT_ADDRESS`, `$AKASH_PASSWORD`.

Then we need our two certs in the current directory in these files.

```
root@k8s-master:~# ls
key.pem provider-cert.pem
```

Then run the helm install and pass in the relevant options.

```
helm install provider akash/provider \
     --set akash_client.from="$AKASH_ACCOUNT_ADDRESS" \
     --set akash_client.keysecret="$(echo -n $AKASH_PASSWORD | base64)" \
     --set akash_client.key="$(cat ./key.pem | base64)" \
     --set akash_provider.providercert="$(cat ./provider-cert.pem | base64)" \
     --set akash_client.node="http://rpc.test1.ewr1.aksh.pw:80/token/$TOKEN/" \
     --set akash_client.chain-id=akash-testnet-1
```

You'll see a provider pod starts in the default namespace and connects.

```
# kubectl get pods
NAME                              READY   STATUS    RESTARTS   AGE
akash-provider-7fcd75b566-mkg6p   1/1     Running   0          46m
```
