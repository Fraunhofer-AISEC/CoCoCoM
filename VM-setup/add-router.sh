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

# Description: This script configures the router of the VPN for the peer.
# Must be called after add-peer.sh


SOURCE_DIR=$(realpath $(dirname "$0"))

# Checks
# --------------------------------------------------------------

if [ $# != 3 ]; then
  echo "Requiring <base64 router publickey> <IP index> <server:port>"
  echo "The first to values are provided by the router after calling add-peer.sh"
  echo "You have to provide the third value."
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

# check if decimal number
re='^[0-9]+$'
if ! [[ "$2" =~ $re ]] || [ "$2" -gt 255 ]; then
  echo "ERROR: IP index is not a number between [0, 255]."
  exit 1
fi

# Setup
# --------------------------------------------------------------
peer_conf="$SOURCE_DIR/peer.conf"

# extend config
echo -e "\n\
[Peer]\n\
PublicKey = $1\n\
Endpoint = $3\n\
AllowedIPs = 192.168.18.0/24, 192.168.18.1/32\n
PersistentKeepAlive = 1" >>"$peer_conf"

"$SOURCE_DIR/start-wireguard-interface.sh" "$2"
