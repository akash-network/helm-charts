#!/bin/bash
set -x

#Install utils
apt update && apt -y --no-install-recommends install ca-certificates curl jq > /dev/null 2>&1

#Check if Home data exists, if not create it.
if [ ! -d "$AKASH_HOME/data" ]
then
/bin/akash init --chain-id "$AKASH_CHAIN_ID" "$AKASH_MONIKER"
cd $AKASH_HOME/data
curl -s "$AKASH_NET/genesis.json" > "$AKASH_HOME/config/genesis.json"
if [ "$AKASH_STATESYNC_ENABLE" == true ]; then
  echo "state-sync is enabled, figure the right trust height & derive its hash"

  SNAP_RPC1="{{ .Values.state_sync.rpc1 }}"
  SNAP_RPC2="{{ .Values.state_sync.rpc2 }}"

  LATEST_HEIGHT=$(curl -Ls $SNAP_RPC1/block | jq -r .result.block.header.height)
  HEIGHT_OFFSET={{ .Values.state_sync.height_offset }}
  BLOCK_HEIGHT=$((LATEST_HEIGHT - HEIGHT_OFFSET))
  TRUST_HASH=$(curl -Ls "$SNAP_RPC1/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

  echo "TRUST HEIGHT: $BLOCK_HEIGHT"
  echo "TRUST HASH: $TRUST_HASH"

  export AKASH_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
  export AKASH_STATESYNC_TRUST_HASH=$TRUST_HASH

else
  apt -y --no-install-recommends install aria2 > /dev/null 2>&1
    if [ "$SNAPSHOT_POLKACHU" == true ]; then
      apt -y --no-install-recommends install lz4 > /dev/null 2>&1
      SNAPSHOT_URL=$(curl -s https://polkachu.com/tendermint_snapshots/akash | grep tar.lz4 | head -n1 | grep -io '<a href=['"'"'"][^"'"'"']*['"'"'"]' |   sed -e 's/^<a href=["'"'"']//i' -e 's/["'"'"']$//i')
      echo "Using latest Polkachu blockchain snapshot, $SNAPSHOT_URL"
      aria2c --out=snapshot.tar.lz4 --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 16 -x 16 -k 1M -j 1 $SNAPSHOT_URL
      lz4 -c -d snapshot.tar.lz4 | tar -x -C $AKASH_HOME
      rm -f snapshot.tar.gz
    else
      SNAPSHOT_URL=$(curl -s https://cosmos-snapshots.s3.filebase.com/akash/pruned/snapshot.json | jq -r .latest)
      echo "Using latest Cosmos blockchain snapshot, $SNAPSHOT_URL"
      aria2c --out=snapshot.tar.gz --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 16 -x 16 -k 1M -j 1 $SNAPSHOT_URL
      tar -zxvf snapshot.tar.gz
      rm -f snapshot.tar.gz
    fi
fi
/bin/akash start
else
  echo "Found Akash data folder!"
  cd $AKASH_HOME/data
  /bin/akash start
fi

if [[ $AKASH_DEBUG == "true" ]]; then sleep 5000; fi
