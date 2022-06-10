## Akash E2E Tests

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
