#!/bin/bash
set -x

if [ ! -d "$AKASH_HOME/data" ]
then
  /bin/akash init --chain-id "$AKASH_CHAIN_ID" "$AKASH_MONIKER"
fi

apt update && apt -y install curl > /dev/null 2>&1
curl -s "$AKASH_NET/genesis.json" > "$AKASH_HOME/config/genesis.json"

if [[ $AKASH_NET == "https://raw.githubusercontent.com/ovrclk/net/master/mainnet" ]]
then
  apt -y install jq aria2 > /dev/null 2>&1
  rm -rf $AKASH_HOME/data ; mkdir -p $AKASH_HOME/data ; cd $AKASH_HOME/data
  SNAPSHOT_URL=$(curl https://cosmos-snapshots.s3.filebase.com/akash/pruned/snapshot.json | jq -r .latest)
  echo "Using latest blockchain snapshot, $SNAPSHOT_URL" ; aria2c --out=snapshot.tar.gz --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 16 -x 16 -k 1M -j 1 $SNAPSHOT_URL
  tar -zxvf snapshot.tar.gz
  rm -f snapshot.tar.gz
fi

/bin/akash start
if $AKASH_DEBUG == "true"; then sleep 5000; fi
