#!/bin/bash
# Filename: wait_for_rpc.sh

set -x

##
# Check the Akash Node is working
##
apt update && apt -yqq install curl jq bc netcat ca-certificates

# fail fast should there be a problem installing curl, jq, nc packages
type curl || exit 1
type jq || exit 1
type nc || exit 1

solo_ip=$(echo $AKASH_NODE | cut -d":" -f2 | cut -d"/" -f3)
port=$(echo $AKASH_NODE | cut -d":" -f3 | cut -d"/" -f1)
if [[ $AKASH_NODE != "http://akash-node-1:26657" ]]; then
  nc -z -v -w5 $solo_ip $port
fi
until [[ $(curl -s $AKASH_NODE/status | jq -r .result.sync_info.catching_up) == "false" ]]; do sleep 15; echo "Akash node not ready. Retrying";  done

# Check Akash RPC node isn't running behind too much and abort if it does.
DATE_AKASH=$(curl -s $AKASH_NODE/status | jq -r '.result.sync_info.latest_block_time')
TS_AKASH=$(date +%s --date "$DATE_AKASH")
TS=$(date +%s)
DIFF=$(echo "$TS - $TS_AKASH" | bc)
if [[ "$DIFF" -gt 30 ]]; then
  echo "Akash RPC $AKASH_NODE is running $DIFF seconds behind."
  echo "ACTION: Make sure your system time in synchronized and/or check your Akash RPC node."
  exit 1
elif [[ "$DIFF" -lt -30 ]]; then
  echo "Akash RPC $AKASH_NODE is running $DIFF seconds ahead."
  echo "ACTION: Make sure your system time in synchronized and/or check your Akash RPC node."
  exit 1
else
  echo "Last block Akash RPC $AKASH_NODE seen was $DIFF seconds ago => OK"
fi
