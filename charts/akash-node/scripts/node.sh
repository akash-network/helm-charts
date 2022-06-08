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
  apt -y install jq aria2 wget nmap > /dev/null 2>&1
  rm -rf $AKASH_HOME/data ; mkdir -p $AKASH_HOME/data ; cd $AKASH_HOME/data
  SNAPSHOT_URL=$(curl https://cosmos-snapshots.s3.filebase.com/akash/pruned/snapshot.json | jq -r .latest)
  echo "Using latest blockchain snapshot, $SNAPSHOT_URL" ; aria2c --out=snapshot.tar.gz --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 16 -x 16 -k 1M -j 1 $SNAPSHOT_URL
  tar -zxvf snapshot.tar.gz
  rm -f snapshot.tar.gz
  echo "Get working peers to sync an RPC node with!"
  wget https://raw.githubusercontent.com/ovrclk/net/master/mainnet/peer-nodes.txt
  ip=$(cat peer-nodes.txt)
  for i in $ip; do
    original=$i ; i=$(echo $i | cut -d@ -f2-)
    solo_ip=$(echo $i | cut -f1 -d":")
    port=$(echo $i | cut -d":" -f2-)
    nmap -p $port $solo_ip | grep "down" &> /dev/null
    if [ $? == 0 ]; then
      echo "$solo_ip is unreachable"
    else
      echo "$original" >> good-nodes.txt
    fi
  done
  export AKASH_P2P_PRIVATE_PEER_IDS=$(cat good-nodes.txt | shuf -n 1)
fi

/bin/akash validate-genesis
/bin/akash start
if $AKASH_DEBUG == "true"; then sleep 5000; fi
