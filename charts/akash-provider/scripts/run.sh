#!/bin/bash

# livenessProbe is going to check the provider log for errors
exec &> >(tee -a "/var/log/provider.log")

# Install apps required by the bid price script
apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install curl jq bc ca-certificates

exec provider-services run
