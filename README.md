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

You'll need a Kubernetes cluster. We recommend using Kubespray or Rancher Kubernetes Engine when deploying to bare metal. But really any Kubernetes cluster will work.

Then, you need a funded wallet on the network that you would like to setup. In this documentation we'll use the `testnet`. But in production environments you will want to use `mainnet`.

Once you have a funded wallet export your private key with a password.

Put your private key into a file named `key.pem` in the current directory.

### Setup some variables used by the Helm Charts

Set your KUBECONFIG to the cluster you want to install on.

Decide what Net you would like to run. Either mainnet, testnet or edgenet.

```
AKASH_NET=testnet
```

Now manually set your public wallet address and the password that can unlock your private key.

Also, set the public DNS zone you would like to use.

```
ACCOUNT_ADDRESS=        # Your Akash public wallet address
KEY_SECRET=             # The password you used when you exported your private key
DOMAIN=my.domain.com    # A top level domain
```

Use these variables to construct some Akash variables. You can copy and paste this block.

```
NET_URL=https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET
NODE=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/rpc-nodes.txt" | head -1)
CHAIN_ID=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/chain-id.txt")
PEERS=$(curl -s "https://raw.githubusercontent.com/ovrclk/net/master/$AKASH_NET/peer-nodes.txt" | sed "N;s/\n/,/")
```

We also need some namespaces to exist.

```
kubectl create ns akash-services
kubectl create ns ingress-nginx
```

And we need to label our nodes so that our Ingress runs.

```
kubectl label nodes k8s-node-0 akash.network/role=ingress
kubectl label nodes k8s-node-1 akash.network/role=ingress
```

#### Akash Node Install

Install an Akash node. You can copy and paste all of these helm commands.

```
helm install akash-node akash/akash-node -n akash-services \
     --set akash_node.from=$ACCOUNT_ADDRESS \
     --set akash_node.key=$(cat ./key.pem | base64) \
     --set akash_node.keysecret=$(echo $KEY_SECRET | base64) \
     --set akash_node.node=$NODE \
     --set akash_node.chain_id=$CHAIN_ID \
     --set akash_node.moniker=$DOMAIN \
     --set akash_node.net=$NET_URL \
     --set akash_node.peers=$PEERS \
     --set ingress.enabled=true \
     --set ingress.domain=$DOMAIN
```

#### Akash Provider Install

Install an Akash provider that connects to your Akash node.

```
helm install akash-provider akash/provider -n akash-services \
     --set from=$ACCOUNT_ADDRESS \
     --set key=$(cat ./key.pem | base64) \
     --set keysecret=$(echo $KEY_SECRET | base64) \
     --set node=$NODE \
     --set chainid=$CHAIN_ID \
     --set domain=$DOMAIN
```

#### Akash HostName Operator

Install a Hostname Operator that automates exposing Akash deployments.

```
helm install hostname-operator akash/hostname-operator -n akash-services
```

#### Akash Inventory Operator (Optional - for Persistent Storage)

Install an Inventory Operator that is used for persistent storage. Specifically it reports the free space available to the Akash Provider. You will also need to install and configure the Rook Ceph helm chart on your cluster.

```
helm install inventory-operator akash/inventory-operator -n akash-services
```

#### Akash Rook (Optional - for Persistent Storage)

Install Rook-Ceph on your cluster.

```
helm install akash-rook akash/akash-rook -n rook-ceph
```

### Setup DNS

We defined a $DOMAIN which all of the charts will use for their ingress routes. For our example lets define ours as `myenvironment.example.com`.

The Provider chart creates an ingress-nginx controller that runs on every Kubernetes worker node and binds to port 80 and 443.

Therefore the DNS structure should look something like this:

```
an a record for myenvironment.example.com which contains the ip addresses of all Kubernetes workers
a cname record for rpc.myenvironment.example.com pointing to myenvironment.example.com
a cname record for p2p.myenvironment.example.com pointing to myenvironment.example.com
a cname record for provider.myenvironment.example.com pointing to myenvironment.example.com
a cname record for *.ingress.myenvironment.example.com pointing to myenvironment.example.com
```

Once setup you should be able to curl the following endpoints:

```
curl http://rpc.myenvironment.example.com/status
curl -k https://provider.myenvironment.example.com/status
```

You can put the rpc endpoint behind an SSL load balancer if you wish (although http is also fine).

The provider endpoint uses TLS that matches a certficate stored on the blockchain so better to leave this alone.

Your deployments should also be available under <id>.ingress.myenvironment.example.com
