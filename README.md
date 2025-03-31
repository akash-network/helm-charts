# Documentation

Please refer to the https://docs.akash.network for Helm-Chart based installation instructions.

## Charts

| Chart                    | Description                                                             |
| ------------------------ | ----------------------------------------------------------------------- |
| akash-node               | Installs an Akash RPC node (required)                                   |
| akash-provider           | Installs an Akash provider (required)                                   |
| akash-hostname-operator  | An operator to map Ingress objects to Akash deployments (required)      |
| akash-inventory-operator | An operator  for inventory discovery, labeling, and reporting (required)|
| akash-ip-operator        | An operator required for ip marketplace (optional)                      |

---

### Versioning & Release Process (For Contributors)

We use a two-branch workflow for safely testing and releasing Helm charts in this repo:

- **`devel` branch** – for testing, RC (release candidate) versions, and in-progress changes  
- **`main` branch** – for stable, production-ready chart releases

#### 1. `devel` Branch Workflow

- All development work — including *release candidates* — must go through the `devel` branch.  
- When opening a new PR for an RC version or test changes, always set the base branch to `devel` ⚠️  
- To test charts from `devel`, use the special `akash-dev` Helm repo:  

```sh
helm repo add akash-dev https://akash-network.github.io/helm-charts/dev
helm search repo akash-dev --devel
```

Example output:

```sh
$ helm search repo akash-dev --devel
NAME                               	CHART VERSION	APP VERSION	DESCRIPTION
akash-dev/akash-hostname-operator 	11.5.8-rc3   	0.6.10-rc3 	Maps Ingress objects to Akash deployments
akash-dev/akash-inventory-operator	11.5.8-rc3   	0.6.10-rc3 	Inventory discovery and reporting
akash-dev/akash-ip-operator       	11.5.8-rc3   	0.6.10-rc3 	IP marketplace support (optional)
akash-dev/provider                	11.5.8-rc3   	0.6.10-rc3 	Installs an Akash provider (required)
```

You can use both the **main** and **dev** helm-chart repos side by side:

```sh
$ helm repo list | grep -E '^NAME|^akash'
NAME       	URL                                            
akash      	https://akash-network.github.io/helm-charts    
akash-dev  	https://akash-network.github.io/helm-charts/dev
```

#### 2. Versioning Workflow

Here’s the full versioning lifecycle using `akash/provider` as an example:

- **Initial State**  
  The chart version in the `main` branch is a stable release (e.g., `11.6.3`).

- **Testing Phase**  
  - In the `devel` branch, bump the chart version to a release candidate (e.g., `11.6.4-rc0`).
  - Push to `akash-dev` Helm repo for testing and validation.

- **Release Phase**  
  - Once the RC is verified, cherry-pick or merge relevant commits from `devel` into `main`.
  - Update the version from `11.6.4-rcX` → `11.6.4` (remove `-rcX`) in `main`.

- **Post-Release Sync**  
  After releasing, merge `main` back into `devel` to sync the branches and avoid drift.

#### Rationale

This workflow prevents overlap between RCs and final release versions in `main`, which helps avoid version conflicts when using `helm search repo --devel`.  
Without this separation, Helm hides RCs once a final version with the same number is published — making RCs effectively invisible for testing.

---

> The following sections will be moved to https://docs.akash.network eventually.

### Troubleshooting

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
