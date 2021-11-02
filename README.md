## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```
helm repo add akash https://ovrclk.github.io/helm-charts
```

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages. You can then run `helm search repo akash` to see the charts.

## Setting up a new TestNet Full-Node and Provider

Firstly, you need a funded wallet. Once you have that export your private key with a password.

Put your private key into a file named key.pem in the current directory.

You also need to put a copy of your Provider cert into provider-cert.pem in the current directory.

### Setup some variables used by the Helm Charts

```
AKASH_ACCOUNT_ADDRESS=myaccountaddress
AKASH_KEY=$(cat ./key.pem)
AKASH_KEY_SECRET=mysecret
AKASH_NET=testnet
AKASH_CHAIN_ID=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/chain-id.txt)
AKASH_PEERS=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/{{ net }}/peer-nodes.txt" | sed "N;s/\n/,/")
DOMAIN=my.domain.com
PROVIDER_CERT=$(cat ./provider-cert.pem)
```

#### Akash Node Install

```
helm install akash-node akash/akash-node \
     --set akash_node.from=$AKASH_ACCOUNT_ADDRESS \
     --set akash_node.key=$AKASH_KEY \
     --set akash_node.keysecret=$AKASH_KEY_SECRET \
     --set akash_node.chain_id=$AKASH_CHAIN_ID \
     --set akash_node.moniker=$DOMAIN \
     --set akash_node.net=$AKASH_NET \
     --set akash_node.peers=$AKASH_PEERS \
     --set ingress.enabled=true \
     --set ingress.domain=$DOMAIN
```

#### Akash Provider Install
```
helm install akash-provider akash/akash-provider \
     --set akash_client.from=$AKASH_ACCOUNT_ADDRESS \
     --set akash_client.key=$AKASH_KEY \
     --set akash_client.keysecret=$AKASH_KEY_SECRET \
     --set akash_client.chain_id=$AKASH_CHAIN_ID \
     --set akash_provider.providercert=$PROVIDER_CERT
```

#### Akash Inventory Operator

```
helm install akash-provider akash/inventory-operator
```

#### Akash HostName Operator

```
helm install akash-provider akash/hostname-operator
     --set ingress.enabled=true \
     --set ingress.domain=$DOMAIN
```
