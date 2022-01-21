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

You can try a lightweight Kubernetes [k3s](https://k3s.io/), it brings you a fully fledged Kubernetes in under 30 seconds! Quick hint on k3s to save your time: run k3s with `--disable traefik` or delete traefik LoadBalancer after k3s installation `kubectl -n kube-system delete svc traefik` so to not interfere with `ingress-nginx-controller`.

Then, you need a funded wallet on the network that you would like to setup. In this documentation we'll use the `mainnet` which is the default in the chart. But you can override values to point to any other net.

Once you have a funded wallet export your private key with a password.

Put your private key into a file named `key.pem` in the current directory.

### Setup some variables used by the Helm Charts

Set your KUBECONFIG to the cluster you want to install on.

Now manually set your public wallet address and the password that can unlock your private key.

```
ACCOUNT_ADDRESS=        # Your Akash public wallet address
KEY_SECRET=             # The password you used when you exported your private key
DOMAIN=my.domain.com    # A top level domain
CHAINID=                # The chain ID of the network you are connecting to
MONIKER=mynode          # A unique name for your Akash node
```

#### Create namespace

Make sure to create these namespaces used by Helm Charts first.

> Note that `ingress-nginx` namespace **must** have `app.kubernetes.io/name=ingress-nginx` label which is used by [akash-deployment-restrictions netpol](https://github.com/ovrclk/akash/blob/4a188686a68b3f7fbdc51b14dd8bff4b6689d94e/provider/cluster/kube/builder/netpol.go#L73)

```
kubectl create ns akash-services
kubectl label ns akash-services akash.network/name=akash-services akash.network=true

kubectl create ns ingress-nginx
kubectl label ns ingress-nginx app.kubernetes.io/name=ingress-nginx app.kubernetes.io/instance=ingress-nginx
```

Namespace references:

- [akash-services](https://raw.githubusercontent.com/ovrclk/akash/master/_docs/kustomize/networking/namespace.yaml)
- [ingress-nginx](https://raw.githubusercontent.com/ovrclk/akash/mainnet/main/_run/ingress-nginx.yaml)

#### Akash Node Install

Install an Akash node. You can copy and paste all of these helm commands.

```
helm install akash-node akash/akash-node -n akash-services \
     --set akash_node.from="$ACCOUNT_ADDRESS" \
     --set akash_node.key="$(cat ./key.pem | base64)" \
     --set akash_node.keysecret="$(echo $KEY_SECRET | base64)" \
     --set akash_node.moniker="$MONIKER"
```

#### Akash Provider Install

Install an Akash provider that connects to your Akash node.

```
helm install akash-provider akash/provider -n akash-services \
     --set from="$ACCOUNT_ADDRESS" \
     --set key="$(cat ./key.pem | base64)" \
     --set keysecret="$(echo $KEY_SECRET | base64)" \
     --set domain="$DOMAIN" \
     --set chainid="$CHAINID"
```

#### Akash HostName Operator

Install a Hostname Operator that automates exposing Akash deployments.

```
helm install hostname-operator akash/hostname-operator -n akash-services
```

#### Ingress Install

Install the Ingress configuration for Akash.

```
helm install akash-ingress akash/akash-ingress -n ingress-nginx --set domain=$DOMAIN
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
an A record for nodes.example.com which contains the ip addresses of all Kubernetes worker nodes
a CNAME record for rpc.myenvironment.example.com pointing to nodes.example.com
a CNAME record for grpc.myenvironment.example.com pointing to nodes.example.com
a CNAME record for p2p.myenvironment.example.com pointing to nodes.example.com
a CNAME record for provider.myenvironment.example.com pointing to nodes.example.com
a CNAME record for *.ingress.myenvironment.example.com pointing to nodes.example.com
```

Once setup you should be able to curl the following endpoints:

```
curl http://rpc.myenvironment.example.com:26657/status
curl -k https://provider.myenvironment.example.com:8443/status
```

You can put the rpc endpoint behind an SSL load balancer if you wish (although http is also fine).

The provider endpoint uses TLS that matches a certficate stored on the blockchain so better to leave this alone.

Your deployments should also be available under <id>.ingress.myenvironment.example.com
