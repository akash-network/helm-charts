## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```
helm repo add akash https://ovrclk.github.io/helm-charts
```

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages. You can then run `helm search repo akash` to see the charts.

## Setting up a Full-Node and Provider

Firstly, you need a funded wallet. Once you have that export your private key with a password.

Put your private key into a file named `key.pem` in the current directory.

You also need to put a copy of your Provider cert into `provider-cert.pem` in the current directory.

#### Setup some variables used by the Helm Charts

Set your KUBECONFIGto the cluster you want to install on.

```
AKASH_ACCOUNT_ADDRESS=  # Your Akash public wallet address
AKASH_KEY_SECRET=       # The password you used when you exported your private key
AKASH_NET=testnet       # mainnet, testnet or edgenet
DOMAIN=my.domain.com    # A top level domain to create rpc.my.domain.com and other Akash endpoints
```

#### Akash Node Install

```
helm install akash-node akash/akash-node -n akash-services \
     --set akash_node.from=$AKASH_ACCOUNT_ADDRESS \
     --set akash_node.key=$(cat ./key.pem) \
     --set akash_node.keysecret=$AKASH_KEY_SECRET \
     --set akash_node.chain_id=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/chain-id.txt) \
     --set akash_node.moniker=$DOMAIN \
     --set akash_node.net=$AKASH_NET \
     --set akash_node.peers=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/peer-nodes.txt" | sed "N;s/\n/,/") \
     --set ingress.enabled=true \
     --set ingress.domain=$DOMAIN
```

#### Akash Provider Install
```
helm install akash-provider akash/akash-provider -n akash-services \
     --set akash_client.from=$AKASH_ACCOUNT_ADDRESS \
     --set akash_client.key=$(cat ./key.pem) \
     --set akash_client.keysecret=$AKASH_KEY_SECRET \
     --set akash_client.chain_id=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/chain-id.txt) \
     --set akash_provider.providercert=$(cat ./provider-cert.pem)
```

#### Akash Inventory Operator

```
helm install akash-provider akash/inventory-operator -n akash-services
```

#### Akash HostName Operator

```
helm install akash-provider akash/hostname-operator -n akash-services \
     --set ingress.enabled=true \
     --set ingress.domain=$DOMAIN
```
