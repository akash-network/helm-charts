#!/bin/bash
set -x

if [ ! -d "$AKASH_HOME/data" ]
then
  /bin/akash init --chain-id "$AKASH_CHAIN_ID" "$AKASH_MONIKER"
fi

apt update && apt -y --no-install-recommends install ca-certificates curl jq > /dev/null 2>&1
curl -s "$AKASH_NET/genesis.json" > "$AKASH_HOME/config/genesis.json"

mkdir -p $AKASH_HOME/data
cd $AKASH_HOME/data

if [ "$AKASH_STATESYNC_ENABLE" == true ]; then
  echo "state-sync is enabled, figure the right trust height & derive its hash"

  SNAP_RPC1="{{ .Values.state_sync.rpc1 }}"
  SNAP_RPC2="{{ .Values.state_sync.rpc2 }}"

  echo "update AKASH_P2P_PERSISTENT_PEERS with the state-sync hosts: $SNAP_RPC1, $SNAP_RPC2 ..."
  SNAP_RPC1_ID=$(curl -s ${SNAP_RPC1}/status | jq -r '.result.node_info.id')
  SNAP_RPC2_ID=$(curl -s ${SNAP_RPC2}/status | jq -r '.result.node_info.id')

  SNAP_RPC1_ADDR=$(curl -s ${SNAP_RPC1}/status | jq -r '.result.node_info.other.rpc_address')
  SNAP_RPC2_ADDR=$(curl -s ${SNAP_RPC2}/status | jq -r '.result.node_info.other.rpc_address')

  SNAP_RPC1_PORT=${SNAP_RPC1_ADDR##*:}
  SNAP_RPC2_PORT=${SNAP_RPC2_ADDR##*:}

  T=${SNAP_RPC1#*//}
  SNAP_RPC1_HOST=${T%:*}

  T=${SNAP_RPC2#*//}
  SNAP_RPC2_HOST=${T%:*}

  if [ $SNAP_RPC1_ID == $SNAP_RPC2_ID ]; then
     T="${SNAP_RPC1_ID}@${SNAP_RPC1_HOST}:${SNAP_RPC1_PORT}"
  else
     T="${SNAP_RPC1_ID}@${SNAP_RPC1_HOST}:${SNAP_RPC1_PORT},${SNAP_RPC2_ID}@${SNAP_RPC2_HOST}:${SNAP_RPC2_PORT}"
  fi
  AKASH_P2P_PERSISTENT_PEERS="$AKASH_P2P_PERSISTENT_PEERS,$T"
  export AKASH_P2P_PERSISTENT_PEERS
  echo "AKASH_P2P_PERSISTENT_PEERS: $AKASH_P2P_PERSISTENT_PEERS"

  LATEST_HEIGHT=$(curl -s $SNAP_RPC1/block | jq -r .result.block.header.height)
  HEIGHT_OFFSET={{ .Values.state_sync.height_offset }}
  BLOCK_HEIGHT=$((LATEST_HEIGHT - HEIGHT_OFFSET))
  TRUST_HASH=$(curl -s "$SNAP_RPC1/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

  echo "TRUST HEIGHT: $BLOCK_HEIGHT"
  echo "TRUST HASH: $TRUST_HASH"

  export AKASH_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
  export AKASH_STATESYNC_TRUST_HASH=$TRUST_HASH

else

  apt -y --no-install-recommends install aria2  > /dev/null 2>&1
  SNAPSHOT_URL=$(curl https://cosmos-snapshots.s3.filebase.com/akash/pruned/snapshot.json | jq -r .latest)
  echo "Using latest blockchain snapshot, $SNAPSHOT_URL"
  aria2c --out=snapshot.tar.gz --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 16 -x 16 -k 1M -j 1 $SNAPSHOT_URL
  tar -zxvf snapshot.tar.gz
  rm -f snapshot.tar.gz
fi

/bin/akash start
if $AKASH_DEBUG == "true"; then sleep 5000; fi
