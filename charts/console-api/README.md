## Deploy using

# For mainnet
helm install console-api-mainnet . -f values.yaml -f values-mainnet.yaml

# For sandbox
helm install console-api-sandbox . -f values.yaml -f values-sandbox.yaml
