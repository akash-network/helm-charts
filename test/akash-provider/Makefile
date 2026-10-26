# Local end-to-end environment for the akash-provider chart.
#
#   make up      create the kind cluster (no-op if it already exists)
#   make down    delete the kind cluster
#   make status  show cluster nodes and pods
#   make env     print the KUBECONFIG export for this cluster
#   make localnet       install charts/akash-node as a local chain, wait for blocks
#   make localnet-down  uninstall the local chain
#   make provider       CRDs + namespaces, hostname + inventory operators, provider chart; wait until healthy
#   make provider-down  uninstall the provider and both operators, delete the provider PVC
#   make e2e-up         up + localnet + provider, from nothing to a healthy provider
#   make e2e-reset      fresh chain (new provider key), provider uninstalled, node cert dir wiped
#   make test           up + localnet + e2e-reset, then the bats suite (installs the provider itself)
#   make test-upgrade   upgrade tests: released chart (RELEASED_CHART_COMMIT) → this branch, PVC kept (local only, not in CI)
#
# kind and bats are downloaded (checksum-verified) into .cache/bin, and the cluster's
# kubeconfig is written to .cache/kubeconfig, so ~/.kube/config is not touched.

SHELL        := /bin/bash
.SHELLFLAGS  := -eu -o pipefail -c

ROOT         := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(ROOT)/versions.env

CACHE        := $(ROOT)/.cache
BIN          := $(CACHE)/bin
KIND         := $(BIN)/kind-$(KIND_VERSION)

CLUSTER_NAME ?= akash-provider-e2e
KIND_IMAGE   ?= kindest/node:$(KINDEST_VERSION)@$(KINDEST_DIGEST)
KIND_CONFIG  ?= $(ROOT)/kind-config.yaml

export KUBECONFIG := $(CACHE)/kubeconfig

CHARTS       := $(abspath $(ROOT)/../../charts)
LOCALNET_NS  ?= akash-localnet
# Fixed by the akash-node chart: StatefulSet akash-node-1, Service akash-node-1
LOCALNET_POD := akash-node-1-0
LOCALNET_RPC := http://akash-node-1.$(LOCALNET_NS):26657

PROVIDER_NS  ?= akash-services
# Charts are installed exactly as they are on the branch (image tags come from
# each chart's appVersion); only the CRDs need a version, taken from the provider chart.
PROVIDER_APP_VERSION := $(shell sed -n 's/^appVersion: //p' $(CHARTS)/akash-provider/Chart.yaml)
PROVIDER_KEY_PASS := localnet-pass
PROVIDER_CACHE    := $(CACHE)/provider
CRD_URL      := https://raw.githubusercontent.com/akash-network/provider/v$(PROVIDER_APP_VERSION)/pkg/apis/akash.network/crd.yaml

OS           := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH         := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
KIND_URL     := https://github.com/kubernetes-sigs/kind/releases/download/$(KIND_VERSION)/kind-$(OS)-$(ARCH)

BATS_DIR     := $(CACHE)/bats-core-$(BATS_VERSION:v%=%)
BATS         := $(BATS_DIR)/bin/bats
BATS_URL     := https://github.com/bats-core/bats-core/archive/refs/tags/$(BATS_VERSION).tar.gz

.DEFAULT_GOAL := help

.PHONY: help
help:
	@sed -n 's/^#   //p' $(MAKEFILE_LIST)

$(KIND):
	mkdir -p $(BIN)
	curl -fsSL -o $@.tmp $(KIND_URL)
	echo "$$(curl -fsSL $(KIND_URL).sha256sum | awk '{print $$1}')  $@.tmp" | shasum -a 256 -c -
	chmod +x $@.tmp
	mv $@.tmp $@

$(BATS):
	mkdir -p $(CACHE)
	curl -fsSL -o $(CACHE)/bats.tgz.tmp $(BATS_URL)
	echo "$(BATS_SHA256)  $(CACHE)/bats.tgz.tmp" | shasum -a 256 -c -
	tar -xzf $(CACHE)/bats.tgz.tmp -C $(CACHE)
	rm $(CACHE)/bats.tgz.tmp

.PHONY: up
up: $(KIND)
	@if $(KIND) get clusters | grep -qx '$(CLUSTER_NAME)'; then \
		echo "kind cluster $(CLUSTER_NAME) already exists"; \
	else \
		$(KIND) create cluster --name $(CLUSTER_NAME) --image $(KIND_IMAGE) --config $(KIND_CONFIG) --wait 120s; \
	fi
	# --wait only covers the control plane; the chart also needs DNS and PVCs
	kubectl -n kube-system rollout status deployment/coredns --timeout=120s
	kubectl -n local-path-storage rollout status deployment/local-path-provisioner --timeout=120s
	kubectl get nodes -o wide

.PHONY: down
down: $(KIND)
	$(KIND) delete cluster --name $(CLUSTER_NAME)

.PHONY: status
status:
	kubectl get nodes -o wide
	kubectl get pods -A

.PHONY: localnet
localnet:
	helm upgrade --install akash-node $(CHARTS)/akash-node \
		--namespace $(LOCALNET_NS) --create-namespace \
		-f $(ROOT)/localnet/akash-node-values.yaml \
		--wait --timeout 5m
	$(MAKE) localnet-wait

.PHONY: localnet-wait
localnet-wait:
	kubectl -n $(LOCALNET_NS) wait --for=condition=Ready pod/$(LOCALNET_POD) --timeout=5m
	@for i in $$(seq 1 60); do \
		h=$$(kubectl -n $(LOCALNET_NS) exec $(LOCALNET_POD) -c akash-node -- \
			curl -s localhost:26657/status | sed -n 's/.*"latest_block_height":"\([0-9]*\)".*/\1/p'); \
		if [ "$${h:-0}" -gt 1 ]; then echo "localnet producing blocks, height $$h, rpc $(LOCALNET_RPC)"; exit 0; fi; \
		sleep 2; \
	done; \
	echo "localnet did not produce blocks"; exit 1

.PHONY: localnet-down
localnet-down:
	helm uninstall akash-node --namespace $(LOCALNET_NS) --wait

.PHONY: provider-prereqs
provider-prereqs:
	mkdir -p $(PROVIDER_CACHE)
	curl -fsSL -o $(PROVIDER_CACHE)/crd.yaml $(CRD_URL)
	kubectl apply -f $(PROVIDER_CACHE)/crd.yaml
	# namespaces the provider expects to exist, labelled as in the provider docs
	kubectl create namespace $(PROVIDER_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(PROVIDER_NS) akash.network=true akash.network/name=$(PROVIDER_NS) --overwrite
	kubectl create namespace lease --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace lease akash.network=true --overwrite

.PHONY: hostname-operator
hostname-operator: provider-prereqs
	helm upgrade --install akash-hostname-operator $(CHARTS)/akash-hostname-operator \
		--namespace $(PROVIDER_NS) \
		-f $(ROOT)/localnet/hostname-operator-values.yaml \
		--wait --timeout 3m

# Charts default values: cluster_storage default/beta3/ram, GPU discovery finds none in kind.
.PHONY: inventory-operator
inventory-operator: provider-prereqs
	helm upgrade --install akash-inventory-operator $(CHARTS)/akash-inventory-operator \
		--namespace $(PROVIDER_NS) \
		--wait --timeout 3m

# The localnet chain is recreated with new keys, so export the key every time.
.PHONY: provider-key
provider-key:
	mkdir -p $(PROVIDER_CACHE)
	kubectl -n $(LOCALNET_NS) exec $(LOCALNET_POD) -c akash-node -- \
		sh -c "printf '$(PROVIDER_KEY_PASS)\n$(PROVIDER_KEY_PASS)\n' | akash keys export provider" \
		> $(PROVIDER_CACHE)/key.txt 2>/dev/null
	kubectl -n $(LOCALNET_NS) exec $(LOCALNET_POD) -c akash-node -- akash keys show provider -a \
		> $(PROVIDER_CACHE)/address

# Installed after the operators: the provider looks them up once at start.
.PHONY: provider
provider: hostname-operator inventory-operator provider-key
	helm upgrade --install akash-provider $(CHARTS)/akash-provider \
		--namespace $(PROVIDER_NS) \
		-f $(ROOT)/localnet/provider-values.yaml \
		--set from=$$(cat $(PROVIDER_CACHE)/address) \
		--set key=$$(base64 < $(PROVIDER_CACHE)/key.txt | tr -d '\n') \
		--set keysecret=$$(printf '$(PROVIDER_KEY_PASS)' | base64)
	$(MAKE) provider-wait

# Healthy = the chart's own liveness checks pass inside the provider container.
.PHONY: provider-wait
provider-wait:
	@for i in $$(seq 1 60); do \
		if kubectl -n $(PROVIDER_NS) exec akash-provider-0 -c provider -- timeout 40 /scripts/liveness_checks.sh >/dev/null 2>&1; then \
			echo "provider healthy: liveness checks pass, owner $$(cat $(PROVIDER_CACHE)/address)"; exit 0; \
		fi; \
		sleep 5; \
	done; \
	kubectl -n $(PROVIDER_NS) get pods; echo "provider did not become healthy"; exit 1

.PHONY: provider-down
provider-down:
	-helm uninstall akash-provider --namespace $(PROVIDER_NS) --wait
	-helm uninstall akash-hostname-operator --namespace $(PROVIDER_NS) --wait
	-helm uninstall akash-inventory-operator --namespace $(PROVIDER_NS) --wait
	-kubectl -n $(PROVIDER_NS) delete pvc -l app.kubernetes.io/instance=akash-provider --wait
	-kubectl -n $(PROVIDER_NS) delete pvc home-akash-provider-0 --ignore-not-found --wait

.PHONY: e2e-up
e2e-up: up localnet provider

# The chain lives in an emptyDir: a new node pod is a new chain with a new provider key.
# The provider cert sits in a hostPath on the kind node, so it is wiped there.
.PHONY: e2e-reset
e2e-reset: provider-down
	docker exec $(CLUSTER_NAME)-control-plane rm -rf /root/.akash/k8s-config
	kubectl -n $(LOCALNET_NS) delete pod $(LOCALNET_POD) --wait
	$(MAKE) localnet-wait

.PHONY: test
test: $(BATS) up localnet e2e-reset
	$(BATS) --timing $(ROOT)/bats/provider.bats

# The released chart, taken from git. One fix applied: in 19.0.x the StatefulSet's `env:` sits inside
# the letsEncrypt condition, so the chart does not install with letsEncrypt.enabled=false.
RELEASED_CHART := $(CACHE)/released-$(RELEASED_CHART_COMMIT)/charts/akash-provider
.PHONY: released-chart
released-chart:
	rm -rf $(CACHE)/released-$(RELEASED_CHART_COMMIT) && mkdir -p $(CACHE)/released-$(RELEASED_CHART_COMMIT)
	git -C $(CHARTS)/.. archive $(RELEASED_CHART_COMMIT) charts/akash-provider | tar -x -C $(CACHE)/released-$(RELEASED_CHART_COMMIT)
	perl -0pi -e 's/(          \{\{- if \.Values\.letsEncrypt\.enabled \}\}\n)(          env:\n)/$$2$$1/' $(RELEASED_CHART)/templates/statefulset.yaml
	grep -E '^(version|appVersion):' $(RELEASED_CHART)/Chart.yaml

.PHONY: test-upgrade
test-upgrade: $(BATS) up localnet released-chart
	RELEASED_CHART=$(RELEASED_CHART) $(BATS) --timing $(ROOT)/bats/upgrade.bats

.PHONY: env
env:
	@echo "export KUBECONFIG=$(KUBECONFIG)"
