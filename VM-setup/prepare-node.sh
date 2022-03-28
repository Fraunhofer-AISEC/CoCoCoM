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

# Description: This script prepares for an incoming SEV-encrypted VM on this
#machine.

# Install
# --------------------------------------------------------------
SOURCE_DIR=$(realpath $(dirname "$0"))
cd "$SOURCE_DIR"

peer_conf=peer.conf
peer_public=peer.publickey
peer_private=peer.privatekey
port=51820


# define wireguard interface
wg genkey | tee "$peer_private" | wg pubkey >"$peer_public"
priv=$(cat "$peer_private")
echo -ne "[Interface]\nPrivateKey = $priv\nListenPort = $port\n" >"$peer_conf"
