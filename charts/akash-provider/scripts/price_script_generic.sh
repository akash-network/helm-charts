#!/bin/bash
# WARNING: the runtime of this script should NOT exceed 5 seconds!
# Requirements:
# curl jq bc mawk ca-certificates
set -o pipefail

# Example:
# Say you have some accounts (typically yours) you want your provider bid the cheapest (1uakt, about 0.42 AKT/month),
# you can use the following snippet:
# # Alice: akash1fxa9ss3dg6nqyz8aluyaa6svypgprk5tw9fa4q
# # Bob: akash1fhe3uk7d95vvr69pna7cxmwa8777as46uyxcz8
# if [[ "$AKASH_OWNER" == @(akash1fxa9ss3dg6nqyz8aluyaa6svypgprk5tw9fa4q|akash1fhe3uk7d95vvr69pna7cxmwa8777as46uyxcz8) ]]; then
#   echo 1
#   exit 0
# fi

# Do not bid if the tenant address is not in the list passed with WHITELIST_URL environment variable
if ! [[ -z $WHITELIST_URL ]]; then
  WHITELIST=/tmp/price-script.whitelist
  if ! test $(find $WHITELIST -mmin -10 2>/dev/null); then
    curl -o $WHITELIST -s --connect-timeout 3 --max-time 3 -- $WHITELIST_URL
  fi

  if ! grep -qw "$AKASH_OWNER" $WHITELIST; then
    echo "$AKASH_OWNER is not whitelisted" >&2
    exit 1
  fi
fi

data_in=$(jq .)

## DEBUG
if ! [[ -z $DEBUG_BID_SCRIPT ]]; then
  echo "$(TZ=UTC date -R)" >> /tmp/${AKASH_OWNER}.log
  echo "$data_in" >> /tmp/${AKASH_OWNER}.log
fi

cpu_requested=$(echo "$data_in" | jq -r '(map(.cpu * .count) | add) / 1000')
memory_requested=$(echo "$data_in" | jq -r '(map(.memory * .count) | add) / pow(1024; 3)' | awk '{printf "%.12f\n", $0}')
ephemeral_storage_requested=$(echo "$data_in" | jq -r '[.[] | (.storage[] | select(.class == "ephemeral").size // 0) * .count] | add / pow(1024; 3)' | awk '{printf "%.12f\n", $0}')
hdd_pers_storage_requested=$(echo "$data_in" | jq -r '[.[] | (.storage[] | select(.class == "beta1").size // 0) * .count] | add / pow(1024; 3)' | awk '{printf "%.12f\n", $0}')
ssd_pers_storage_requested=$(echo "$data_in" | jq -r '[.[] | (.storage[] | select(.class == "beta2").size // 0) * .count] | add / pow(1024; 3)' | awk '{printf "%.12f\n", $0}')
nvme_pers_storage_requested=$(echo "$data_in" | jq -r '[.[] | (.storage[] | select(.class == "beta3").size // 0) * .count] | add / pow(1024; 3)' | awk '{printf "%.12f\n", $0}')
ips_requested=$(echo "$data_in" | jq -r '(map(.ip_lease_quantity//0 * .count) | add)')
endpoints_requested=$(echo "$data_in" | jq -r '(map(.endpoint_quantity//0 * .count) | add)')
gpu_units_requested=$(echo "$data_in" | jq -r '[.[] | (.gpu.units // 0) * .count] | add')

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
      echo "$usd_per_akt is not an integer/floating number!" >&2
      exit 1
    fi

    # make sure price is in the permitted range
    if ! (( $(echo "$usd_per_akt > 0" | bc -l) && \
            $(echo "$usd_per_akt <= 1000000" | bc -l) )); then
      echo "$usd_per_akt is outside the permitted range (>0, <=1000000)" >&2
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
# Hetzner: CPX51 with 16CPU, 32RAM, 360GB disk = $65.81
# Akash: `(1.60*16)+(0.80*32)+(0.04*360)` = $65.60
TARGET_CPU="1.60"          # USD/thread-month
TARGET_MEMORY="0.80"       # USD/GB-month
TARGET_HD_EPHEMERAL="0.02" # USD/GB-month
TARGET_HD_PERS_HDD="0.01"  # USD/GB-month (beta1)
TARGET_HD_PERS_SSD="0.03"  # USD/GB-month (beta2)
TARGET_HD_PERS_NVME="0.04" # USD/GB-month (beta3)
TARGET_ENDPOINT="0.05"     # USD for port/month
TARGET_IP="5"              # USD for IP/month
TARGET_GPU_UNIT="100"      # USD/GPU unit a month

total_cost_usd_target=$(bc -l <<< "( \
  ($cpu_requested * $TARGET_CPU) + \
  ($memory_requested * $TARGET_MEMORY) + \
  ($ephemeral_storage_requested * $TARGET_HD_EPHEMERAL) + \
  ($hdd_pers_storage_requested * $TARGET_HD_PERS_HDD) + \
  ($ssd_pers_storage_requested * $TARGET_HD_PERS_SSD) + \
  ($nvme_pers_storage_requested * $TARGET_HD_PERS_NVME) + \
  ($endpoints_requested * $TARGET_ENDPOINT) + \
  ($ips_requested * $TARGET_IP) + \
  ($gpu_units_requested * $TARGET_GPU_UNIT) \
  )")

# average block time: 6.117 seconds (based on the time diff between 8090658-8522658 heights [with 432000 blocks as a shift in between if considering block time is 6.0s "(60/6)*60*24*30"])
# average number of days in a month: 30.437
# (60/6.117)*24*60*30.437 = 429909 blocks per month

total_cost_akt_target=$(bc -l <<<"(${total_cost_usd_target}/$usd_per_akt)")
total_cost_uakt_target=$(bc -l <<<"(${total_cost_akt_target}*1000000)")
cost_per_block=$(bc -l <<<"(${total_cost_uakt_target}/429909)")
total_cost_uakt=$(echo "$cost_per_block" | jq 'def ceil: if . | floor == . then . else . + 1.0 | floor end; .|ceil')
echo $total_cost_uakt
