#!/bin/bash
# WARNING: the runtime of this script should NOT exceed 5 seconds!
set -o pipefail

data_in=$(jq .)

cpu_requested=$(echo "$data_in" | jq -r '(map(.cpu * .count) | add) / 1000')
memory_requested=$(echo "$data_in" | jq -r '(map(.memory * .count) | add) / pow(1024; 3)')
ephemeral_storage_requested=$(echo "$data_in" | jq -r '([.[].storage[] | select(.class == "ephemeral").size // 0] | add) / pow(1024; 3)')
hdd_pers_storage_requested=$(echo "$data_in" | jq -r '([.[].storage[] | select(.class == "beta1").size // 0] | add) / pow(1024; 3)')
ssd_pers_storage_requested=$(echo "$data_in" | jq -r '([.[].storage[] | select(.class == "beta2").size // 0] | add) / pow(1024; 3)')
nvme_pers_storage_requested=$(echo "$data_in" | jq -r '([.[].storage[] | select(.class == "beta3").size // 0] | add) / pow(1024; 3)')

tenant_address=$AKASH_OWNER;
whitelist=$(cat "whitelist.txt")
in_list=false
for address in $whitelist
do
    if [ $tenant_address == $address ]; then
      in_list=true
      break
    fi
done
    if [ $in_list != true ]; then
      exit 1 # this means that they are not whitelisted
    fi
# this means that they are whitelisted

# cache AKT price for 60 minutes to reduce the API pressure as well as to slightly accelerate the bidding (+5s)
CACHE_FILE=/tmp/aktprice.cache
if ! test $(find $CACHE_FILE -mmin -60 2>/dev/null); then
  ## cache expired
  usd_per_akt=$(curl -s --connect-timeout 3 --max-time 3 -X GET 'https://api-osmosis.imperator.co/tokens/v2/price/AKT' -H 'accept: application/json' | jq -r '.price' 2>/dev/null)
  if [[ $? -ne 0 ]] || [[ $usd_per_akt == "null" ]] || [[ -z $usd_per_akt ]]; then
    # if Osmosis API fails, try CoinGecko API
    usd_per_akt=$(curl -s --connect-timeout 3 --max-time 3 -X GET "https://api.coingecko.com/api/v3/simple/price?ids=akash-network&vs_currencies=usd" -H  "accept: application/json" | jq -r '[.[]][0].usd' 2>/dev/null)
  fi

  # update the cache only when API returns a result.
  # this way provider will always keep bidding even if API temporarily breaks (unless pod gets restarted which will clear the cache)
  if [ ! -z $usd_per_akt ]; then
    # check price is an integer/floating number
    re='^[0-9]+([.][0-9]+)?$'
    if ! [[ $usd_per_akt =~ $re ]]; then
      exit 1
    fi

    # make sure price is in the permitted range
    if ! (( $(echo "$usd_per_akt > 0" | bc -l) && \
            $(echo "$usd_per_akt <= 1000000" | bc -l) )); then
      exit 1
    fi

    echo "$usd_per_akt" > $CACHE_FILE
  fi

  # TODO: figure some sort of monitoring to inform the provider in the event API breaks
fi

# Fail if script can't read CACHE_FILE for some reason
set -e
usd_per_akt=$(cat $CACHE_FILE)
set +e

#Price in USD/month
TARGET_MEMORY="1.25"       # USD/GB-month
TARGET_HD_EPHEMERAL="0.08" # USD/GB-month
TARGET_HD_PERS_HDD="0.10"  # USD/GB-month (beta1)
TARGET_HD_PERS_SSD="0.12"  # USD/GB-month (beta2)
TARGET_HD_PERS_NVME="0.14" # USD/GB-month (beta3)
TARGET_CPU="4.50"          # USD/thread-month

total_cost_usd_target=$(bc -l <<<"(($cpu_requested * $TARGET_CPU) + ($memory_requested * $TARGET_MEMORY) + ($ephemeral_storage_requested * $TARGET_HD_EPHEMERAL) + ($hdd_pers_storage_requested * $TARGET_HD_PERS_HDD) + ($ssd_pers_storage_requested * $TARGET_HD_PERS_SSD) + ($nvme_pers_storage_requested * $TARGET_HD_PERS_NVME))")

# average block time: 6.102 seconds
# average number of days in a month: 30.437
# (60/6.102)*24*60*30.437 = 430966 blocks per month

total_cost_akt_target=$(bc -l <<<"(${total_cost_usd_target}/$usd_per_akt)")
total_cost_uakt_target=$(bc -l <<<"(${total_cost_akt_target}*1000000)")
cost_per_block=$(bc -l <<<"(${total_cost_uakt_target}/430966)")
total_cost_uakt=$(echo "$cost_per_block" | jq 'def ceil: if . | floor == . then . else . + 1.0 | floor end; .|ceil')
echo $total_cost_uakt
