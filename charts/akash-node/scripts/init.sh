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

  # Make sure we state-sync the node first if it has never been synced before
  export AKASH_HALT_HEIGHT=$LATEST_HEIGHT
  /bin/akash start

else
  if [ "$AKASH_CHAIN_ID" == "akashnet-2" ]; then
    apt -y --no-install-recommends install aria2 lz4 liblz4-tool wget > /dev/null 2>&1
    case "$SNAPSHOT_PROVIDER" in

      "polkachu")
        SNAPSHOTS_DIR_URL="https://snapshots.polkachu.com/snapshots/"
        USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        LATEST=$(curl -s -A "$USER_AGENT" "$SNAPSHOTS_DIR_URL" | grep -oP 'akash/[^<]+\.tar\.lz4' | tail -n1)
        SNAPSHOT_URL="https://snapshots.polkachu.com/snapshots/"
        aria2c --out=snapshot.tar.lz4 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 8 -x 8 -k 1M -j 1 "${SNAPSHOT_URL}${LATEST}"
        lz4 -c -d snapshot.tar.lz4 | tar -x -C "$AKASH_HOME"
        rm -rf snapshot.tar.lz4
        ;;

      "autostake") #Snapshot is not available as of 14/11/2023
        SNAP_URL="http://snapshots.autostake.com/$AKASH_CHAIN_ID/"
        SNAP_NAME=$(curl -s "${SNAP_URL}" | egrep -o "$AKASH_CHAIN_ID" | tr -d ">" | tail -1)
        aria2c --out=snapshot.tar.lz4 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 8 -x 8 -k 1M -j 1 "${SNAP_URL}${SNAP_NAME}"
        lz4 -c -d snapshot.tar.lz4 | tar -x -C "$AKASH_HOME"
        rm -rf snapshot.tar.lz4
        ;;

      "c29r3")
        SNAP_NAME=$(curl -s https://snapshots.c29r3.xyz/akash/ | egrep -o ">$AKASH_CHAIN_ID.*tar" | tr -d ">")
        echo "Using default c29r3.xyz blockchain snapshot, https://snapshots.c29r3.xyz/akash/${SNAP_NAME}"
        aria2c --out=snapshot.tar --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 8 -x 8 -k 1M -j 1 "https://snapshots.c29r3.xyz/akash/${SNAP_NAME}"
        tar -xf snapshot.tar -C "$AKASH_HOME/data"
        rm -rf snapshot.tar
        ;;

      *)
        SNAPSHOTS_DIR_URL="https://snapshots.polkachu.com/snapshots/"
        USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        LATEST=$(curl -s -A "$USER_AGENT" "$SNAPSHOTS_DIR_URL" | grep -oP 'akash/[^<]+\.tar\.lz4' | tail -n1)
        SNAPSHOT_URL="https://snapshots.polkachu.com/snapshots/"
        aria2c --out=snapshot.tar.lz4 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 8 -x 8 -k 1M -j 1 "${SNAPSHOT_URL}${LATEST}"
        lz4 -c -d snapshot.tar.lz4 | tar -x -C "$AKASH_HOME"
        rm -rf snapshot.tar.lz4
        ;;

    esac

  fi
fi
else
  echo "Found Akash data folder!"
  cd "$AKASH_HOME/data" || exit
fi

if [[ $AKASH_DEBUG == "true" ]]; then sleep 5000; fi