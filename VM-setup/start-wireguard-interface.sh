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

### Description: This script starts a previously configured wg-interface as specified in peer_conf

SOURCE_DIR=$(realpath $(dirname "$0"))

# Checks
# --------------------------------------------------------------

# check first argument int and between [0,255]
re='^[0-9]+$'
if ! [[ "$1" =~ $re ]] || [ "$1" -gt 255 ]; then
  echo "Error: requires a number (IP index between [0,255])"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Please run script as root."
  exit 1
fi

# Setup
# --------------------------------------------------------------
peer_conf="$SOURCE_DIR/peer.conf"

ip link del wg0
ip link add dev wg0 type wireguard
ip address add "192.168.18.$1/32" dev wg0
wg setconf wg0 "$peer_conf"
ip link set up dev wg0
ip route add 192.168.18.0/24 dev wg0
# important for router, not so much for other peers
iptables -I FORWARD -i wg0 -o wg0 -j ACCEPT

# Ping router once so routing is known
ping -c 1 192.168.18.1 2>&1 >/dev/null
echo "Setup success"
