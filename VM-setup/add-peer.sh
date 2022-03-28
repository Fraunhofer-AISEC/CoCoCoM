#!/bin/bash
# Copyright 2020-2021 Joana Pecholt, Fraunhofer AISEC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Description: This script adds the provided peer to the VPN router and prints
# out further instructions.

SOURCE_DIR=$(realpath $(dirname "$0"))

# Checks
# --------------------------------------------------------------

if [[ "$#" -ne 1 ]]; then
  echo -e "Run with: \n.add-peer.sh <peer publickey base64>"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Please run script as root."
  exit 1
fi

# check if base64 encoded
ret=$(echo "$1" | base64 --decode 2>/dev/null)
if [ "$?" -ne 0 ]; then
  echo "ERROR: Provided key is not base64 encoded."
  exit 1
fi

# Setup
# --------------------------------------------------------------
peer_conf="$SOURCE_DIR/peer.conf"
peer="$1"

# router public key - needed for printed out command
router_public=$(wg | grep "public key: " | awk '{print $3}')

# Obtain next IP index
last_ip=$(grep AllowedIPs "$peer_conf" | tail -n 1 | awk -F'=' '{print $2}' | awk -F' ' '{print $(NF)}' | awk -F'/' '{print $1}' | awk -F'.' '{print $4}')
if [[ "$last_ip" == "" ]]; then last_ip=1; fi
ip_index=$((last_ip + 1))

# extend router config
echo -e "\n\
[Peer]\n\
PublicKey = $peer\n\
AllowedIPs = 192.168.18.$ip_index/32\n" >>"$peer_conf"

# update wireguard with config
# All existing connections will be reset -> we have to ping the router from all peers again
wg setconf wg0 "$peer_conf"

# Print information for next step in setup
echo -e "On the worker node, call \n./add-router.sh $router_public $ip_index \nadd the public IP and port at the end\n"
