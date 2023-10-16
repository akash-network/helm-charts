#!/bin/bash
set -x

#Install utils
apt update && apt -y --no-install-recommends install ca-certificates curl jq > /dev/null 2>&1

# fail fast should there be a problem installing curl / jq packages
type curl || exit 1
type jq || exit 1

#Check if Home data exists, if not create it.
if [ ! -d "$AKASH_HOME/data" ]
then
/bin/akash init --chain-id "$AKASH_CHAIN_ID" "$AKASH_MONIKER"
cd "$AKASH_HOME/data" || exit
curl -s "$AKASH_NET/genesis.json" > "$AKASH_HOME/config/genesis.json"
if [ "$AKASH_STATESYNC_ENABLE" == true ]; then
  echo "state-sync is enabled, figure the right trust height & derive its hash"

  export SNAP_RPC1="{{ .Values.state_sync.rpc1 }}"
  export SNAP_RPC2="{{ .Values.state_sync.rpc2 }}"

  LATEST_HEIGHT=$(curl -Ls "$SNAP_RPC1/block" | jq -r .result.block.header.height)
  HEIGHT_OFFSET="{{ .Values.state_sync.height_offset }}"
  BLOCK_HEIGHT=$((LATEST_HEIGHT - HEIGHT_OFFSET))
  TRUST_HASH=$(curl -Ls "$SNAP_RPC1/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

  echo "TRUST HEIGHT: $BLOCK_HEIGHT"
  echo "TRUST HASH: $TRUST_HASH"

  export AKASH_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
  export AKASH_STATESYNC_TRUST_HASH=$TRUST_HASH

else
  if [ "$AKASH_CHAIN_ID" == "akashnet-2" ]; then
    apt -y --no-install-recommends install aria2 lz4 liblz4-tool wget > /dev/null 2>&1
    case "$SNAPSHOT_PROVIDER" in

      "polkachu")
        SNAPSHOT_URL=$(curl -s https://polkachu.com/tendermint_snapshots/akash | grep tar.lz4 | head -n1 | grep -io '<a href=['"'"'"][^"'"'"']*['"'"'"]' | sed -e 's/^<a href=["'"'"']//i' -e 's/["'"'"']$//i')
        echo "Using latest Polkachu blockchain snapshot, $SNAPSHOT_URL"
        aria2c --out=snapshot.tar.lz4 --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 4 -x 4 -k 1M -j 1 "$SNAPSHOT_URL"
        lz4 -c -d snapshot.tar.lz4 | tar -x -C "$AKASH_HOME"
        rm -f snapshot.tar.lz4
        ;;
      "autostake")
        SNAP_URL="http://snapshots.autostake.com/akashnet-2"
        SNAP_NAME=$(curl -s $SNAP_URL/ | egrep -o ">akashnet-2.*.tar.lz4" | tr -d ">" | tail -1)
        echo "Using latest Autostake blockchain snapshot, $SNAP_URL/$SNAP_NAME"
        aria2c --out=snapshot_autostake.tar.lz4 --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 4 -x 4 -k 1M -j 1 "$SNAP_URL/$SNAP_NAME"
        lz4 -c -d snapshot_autostake.tar.lz4 | tar -x -C "$AKASH_HOME"
        rm -f snapshot_autostake.tar.lz4
        ;;

      *)
        SNAPSHOT_URL=$(curl -s https://cosmos-snapshots.s3.filebase.com/akash/pruned/snapshot.json | jq -r .latest)
        echo "Using latest Cosmos blockchain snapshot, $SNAPSHOT_URL"
        aria2c --out=snapshot.tar.gz --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 16 -x 16 -k 1M -j 1 "$SNAPSHOT_URL"
        tar -zxvf snapshot.tar.gz
        rm -f snapshot.tar.gz
        ;;

    esac

  fi
fi
else
  echo "Found Akash data folder!"
  cd "$AKASH_HOME/data" || exit
fi

if [[ $AKASH_DEBUG == "true" ]]; then sleep 5000; fi