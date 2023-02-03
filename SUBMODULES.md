## Submodules

This repo contains a [provider](./provider) submodule which has been initialiize this way:

```
LATEST_TAG=$(curl -s https://api.github.com/repos/akash-network/provider/releases/latest | jq -e -r '.tag_name')
git clone -b $LATEST_TAG --depth=1 https://github.com/akash-network/provider.git
git submodule add ./provider
```

It is used mainly for providing a source to the `crd.yaml` file so we don't have to copy it manually.

GH actions will automatically locate the latest tag, so no manual intervention is necessary.

```
helm-charts$ find . -type l -ls
 26739437      0 lrwxrwxrwx   1 user     user           49 Feb  3 21:57 ./charts/akash-provider/templates/crd.yaml -> ../../../provider/pkg/apis/akash.network/crd.yaml
```
