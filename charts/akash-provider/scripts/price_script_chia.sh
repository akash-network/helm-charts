#!/bin/bash
# Author: Andrew Mello
# Purpose:
# - support Chia mining deployment requests for these miners:
#   - BladeBit
#   - MadMax

data_in=$(jq .)

cpu_total=$(echo "$data_in" | jq 'map(.cpu * .count) | add')
memory_total=$(echo "$data_in" | jq 'map(.memory * .count) | add')
storage_total=$(echo "$data_in" |  python3 -c "import json;import sys;data=json.load(sys.stdin);data = [(x['count'], x['storage']) for x in data];data = [cnt*sum(z['size'] for z in y) for cnt,y in data]; data= sum(data);json.dump(data,sys.stdout)")

cpu_total_threads=$(echo $cpu_total | awk '{print $1/1000}')
memory_gb=$(echo $memory_total | awk '{print $1/1024/1024/1024}')
hd_gb=$(echo $storage_total | awk '{print $1/1024/1024/1024}')


usd_per_akt=$(curl -s -X GET "https://api.coingecko.com/api/v3/coins/akash-network/tickers" -H  "accept: application/json" | jq '.tickers[] | select(.market.name == "Osmosis").converted_last.usd' | head -n1)

#Price in USD
TARGET_MEMORY="1.25"
TARGET_HD="0.25"
TARGET_CPU="4.50"

#Chia Madmax Plotter

chia_madmax_cpu=8
chia_madmax_cpu_max=32

chia_madmax_memory=6
chia_madmax_memory_max=32

chia_madmax_storage=715
chia_madmax_storage_max=3200

#Chia Bladebit Plotter

chia_bladebit_cpu=8
chia_bladebit_cpu_max=256

chia_bladebit_memory=420
chia_bladebit_memory_max=512

chia_bladebit_storage=715
chia_bladebit_storage_max=3200

if (( $(echo "$memory_gb >= $chia_bladebit_memory" | bc -l) && \
      $(echo "$cpu_total_threads >= $chia_bladebit_cpu" | bc -l) )); then
#Bladebit detected
TARGET_CPU="20"
total_cost_usd_target=$(bc -l <<<"($cpu_total_threads * $TARGET_CPU)")
elif (( $(echo "$memory_gb >= $chia_madmax_memory" | bc -l) && \
        $(echo "$cpu_total_threads >= $chia_madmax_cpu" | bc -l) && \
        $(echo "$cpu_total_threads <= $chia_madmax_cpu_max" | bc -l) )); then
#Madmax detected
TARGET_CPU="15"
total_cost_usd_target=$(bc -l <<<"($cpu_total_threads * $TARGET_CPU)")
else
#Normal deployment
total_cost_usd_target=$(bc -l <<<"(($cpu_total_threads * $TARGET_CPU) + ($memory_gb * $TARGET_MEMORY) + ($hd_gb * $TARGET_HD))")
fi

total_cost_akt_target=$(bc -l <<<"(${total_cost_usd_target}/$usd_per_akt)")
total_cost_uakt_target=$(bc -l <<<"(${total_cost_akt_target}*1000000)")
cost_per_block=$(bc -l <<<"(${total_cost_uakt_target}/425940.524781341)")
total_cost_uakt=$(echo "$cost_per_block" | jq 'def ceil: if . | floor == . then . else . + 1.0 | floor end; .|ceil')
echo $total_cost_uakt
