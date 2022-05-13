## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```
helm repo add akash https://ovrclk.github.io/helm-charts
```

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages. You can then run `helm search repo akash` to see the charts.

> If you want to use local charts from this github checkout, specify `./charts/akash-node` instead of `akash/akash-node` on `helm install`.

## Charts

| Chart              | Description                                                        |
| ------------------ | ------------------------------------------------------------------ |
| akash-e2e          | End to end tests to check if a provider is healthy (optional)      |
| akash-ingress      | Installs the Akash Ingress resources (required)                    |
| akash-node         | Installs an Akash RPC node (required)                              |
| akash-provider     | Installs an Akash provider (required)                              |
| akash-rook         | Sets up Rook-Ceph for persistent storage (optional)                |
| akash-operator     | An operator to map Ingress objects to Akash deployments (required) |
| inventory-operator | An operator to required for persistent storage (optional)          |

### Kubernetes (Dependency)

[Kubernetes](https://kubernetes.io/) is an open-source system for automating deployment, scaling, and management of containerized applications. It is a hard dependency for running an Akash Provider.

There are many ways to setup a Kubernetes cluster. Scroll to the bottom of this README for some recommendations on what options we recommend.

### Setup some configuration used by the Helm Charts

Set your KUBECONFIG environment variable to the Kubernetes cluster you want to install on. Ensure you can run commands like `kubectl get nodes` before you continue.

Put your private key into a file named `key.pem` in the current directory. You can do this by running `akash keys export default > key.pem`.

> Note that you may need to `export AKASH_KEYRING_BACKEND=` and set this to "file" or "os" depending on what works for you. Check with "akash keys list" command.

Now manually set your public wallet address and the password that can unlock your private key.

```
ACCOUNT_ADDRESS=                  # Your Akash public wallet e.g. akash keys show default -a
KEY_SECRET=                       # The password you used when you exported your key
DOMAIN=mydomain.com               # A top level domain you own. Helm Chart is gonna get set you `<provider|ingress|api|rpc|grpc|p2p>.mydomain.com` names automatically.
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

#### Akash Node Install (Experimental)

Experimental: It is recommended to run Akash nodes outside of Kubernetes. For example on a virtual machine or server using [Cosmos Omnibus](https://github.com/ovrclk/cosmos-omnibus).

Be aware that there is no persistent storage on this Helm chart so a pod restart will lose the blockchain data and the entire snapshot will need to be downloaded again (approx. 30GB).

This chart will create an Akash node that downloads a snapshot into the pod, extracts it and then starts. This may take some time depending on your internet connection.

```
helm install akash-node akash/akash-node -n akash-services
```

#### Akash Provider Install

Install an Akash provider that connects to a public Akash node.

```
helm install akash-provider akash/provider -n akash-services \
     --set from="$ACCOUNT_ADDRESS" \
     --set key="$(cat ./key.pem | base64)" \
     --set keysecret="$(echo $KEY_SECRET | base64)" \
     --set domain="$DOMAIN"
```

> You can add `--set node="http://akash-node-1:26657"` if you are using the experimental Akash node running inside Kubernetes. Or, if you are running your Akash on your own server `--set node="http://internal-ip:26657"`.

#### Akash Hostname Operator

Install a Hostname Operator that automates exposing Akash deployments.

```
helm install hostname-operator akash/hostname-operator -n akash-services
```

#### Ingress Install

Install the Ingress configuration for Akash.

```
helm install akash-ingress akash/akash-ingress -n ingress-nginx --set domain=$DOMAIN
```

#### Akash Rook (Optional - for Persistent Storage)

Installs the Rook Ceph operator which sets up persistent storage.

Before you install this chart you need to install the CRD's manually.

```
kubectl create -f https://raw.githubusercontent.com/ovrclk/helm-charts/main/charts/akash-rook/crds.yaml
```

Then need to set which nodes to use the disks on. We recommend you use all of the Kubernetes worker nodes.

```
helm install akash-rook akash/akash-rook -n akash-services --set nodes[0].name="mynodename",nodes[0].config=""
```

To set multiple nodes use a comma separated list and increase the decimal index from 0 upwards.

#### Akash Inventory Operator (Optional - for Persistent Storage)

Install an Inventory Operator that is used for persistent storage. Specifically it reports the free space available to the Akash Provider.

```
helm install inventory-operator akash/inventory-operator -n akash-services
```

#### Akash E2E Tests (Optional)

Install the Akash End to End Tests. This requires an Akash primary account with funds. Plus 4 additional accounts (can be empty) that are used for running the tests.

Set the decryption password.

`export KEY_SECRET=<password used when exporting key>`

Copy and paste the exported key into `primarykey.pem`, `check0key.pem`, `check1key.pem`, `check2key.pem` and `check3key.pem` in the current directory.

```
helm install akash-e2e akash/akash-e2e -n akash-services \
     --set keysecret="$(echo $KEY_SECRET | base64)" \
     --set primarykey="$(cat ./primarykey.pem | base64)" \
     --set check0key="$(cat ./check0key.pem | base64)" \
     --set check1key="$(cat ./check1key.pem | base64)" \
     --set check2key="$(cat ./check2key.pem | base64)" \
     --set check3key="$(cat ./check3key.pem | base64)"
```

### Setup DNS

We define a $DOMAIN which all of the charts will use for their ingress routes. For our example lets define ours as `yourdomain.com`.

Add A records with the ip addresses of all Kubernetes worker nodes pointing to nodes.yourdomain.com.

To get the external IP of your worker nodes, run `kubectl get nodes -A -o wide`. If you are using a network at home, use your IP address or dynamic dns.

Therefore the DNS structure should look something like this:

```
*.ingress 300 IN CNAME nodes.yourdomain.com.
api 300 IN CNAME nodes.yourdomain.com.
grpc 300 IN CNAME nodes.yourdomain.com.
nodes 300 IN A x.x.x.x
nodes 300 IN A x.x.x.x
nodes 300 IN A x.x.x.x
p2p 300 IN CNAME nodes.yourdomain.com.
provider 300 IN CNAME nodes.yourdomain.com.
rpc 300 IN CNAME nodes.yourdomain.com.
```

Once setup you should be able to curl the following endpoints:

```
curl http://rpc.myenvironment.example.com:26657/status
curl -k https://provider.myenvironment.example.com:8443/status
```

You can put the rpc endpoint behind an SSL load balancer if you wish (although http is also fine).

The provider endpoint uses TLS that matches a certficate stored on the blockchain so better to leave this alone.

Your deployments should also be available under <id>.ingress.myenvironment.example.com

### Firewall Rules

Open the following ports (TCP) to every Kubernetes worker node.

| Domain     | Port  | Description                                                |
| ---------- | ----- | ---------------------------------------------------------- |
| \*.ingress | 80    | So people can connect to their deployments                 |
| api        | 1317  | The Akash node API port                                    |
| provider   | 8443  | The provider port that clients post the Akash SDL files to |
| grpc       | 9090  | The Akash node GRPC port                                   |
| p2p        | 26656 | The Akash node P2P port                                    |
| rpc        | 26657 | The Akash node RPC port                                    |

## Troubleshooting

To troubleshoot you'll need to know the following.

- We run an ingress-nginx pod on every Kubernetes worker node
- This ingress-nginx pod binds all of the ports listed above to 0.0.0.0 on every Kubernetes worker node
- The DNS A record config above should therefore include all Kubernetes worker nodes so that connections are balanced
- Similarly the firewall ports need to be opened to all Kubernetes worker nodes
- There are Kubernetes Ingress resources (kubectl get ingresses -A) that map the DNS CNAMES to backend services
- Therefore connections from outside can hit ANY Kubernetes worker node and ingress-nginx will proxy to the correct service
- Services (kubectl get services -A) are creates in the akash-services namespace pointing to the pods. These map the Ingress to the Pods.
- The pods in the akash-services namespace created by the Helm charts can run on any Kubernetes worker node and are found by the service by label

For troubleshooting the pods in the akash-services namespace you can tail the logs with `kubectl logs -n akash-services <pod name>`. For the Akash Node and Akash Provider Helm charts you can add `--set debug=true` which will add a long sleep to any failing containers. You can then exec into the pod using `kubectl exec -ti -n akash-services <pod name> -- bash` to debug.

### Setting up Kubernetes on your laptop to test

You can try a lightweight Kubernetes [k3s](https://k3s.io/), it brings you a fully fledged Kubernetes in under 30 seconds! Quick hint on k3s to save your time: install k3s using `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -s -` command OR delete traefik LoadBalancer after k3s installation with `kubectl -n kube-system delete svc traefik` command so to not interfere with `ingress-nginx-controller` used for Akash deployments.

After installing k3s you will want configure the client:

```
mkdir ~/.kube
sudo cat /etc/rancher/k3s/k3s.yaml | tee ~/.kube/config >/dev/null

kubectl get nodes
```

Then, you need a funded wallet on the network that you would like to setup. In this documentation we'll use the `mainnet` which is the default in the chart. But you can override values to point to any other net.

### Setting up Kubernetes on Bare Metal

We recommend using Kubespray or Rancher Kubernetes Engine when deploying to bare metal.
