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

# Description: This script injects a specified secret into a initialized
# SEV-encrypted VM on this machine.


if [[ "$#" != 1 ]]; then
  echo "Run with ./inject.sh <path>"
  echo "Injects the secret in the path into the socket of the VM (in same directory)."
  echo "Requires packaged_secret.bin, packaged_secret_header.bin, qmp-sock"
  exit 1
fi

BASE_PATH="${1%/}"
if [ ! -d "$BASE_PATH" ]; then
  echo "ERROR: path does not exist?"
  exit 1
fi
QMP_SOCK="qmp_sock"
SECRET=$(cat "$BASE_PATH/packaged_secret.bin" | base64)
SECRET_HEADER=$(cat "$BASE_PATH/packaged_secret_header.bin" | base64)

# execute command
return=$( (
  echo
  sleep .01
  echo '{ "execute": "qmp_capabilities" }'
  sleep .01
  echo '{ "execute": "sev-inject-launch-secret", "arguments": { "packet-header": "'$SECRET_HEADER'", "secret": "'$SECRET'"}}'
  sleep .01
) | nc -U "$BASE_PATH/$QMP_SOCK" -N)

if [[ "$return" == *"error"* ]]; then
  echo "Error detected during launch secret inject."
  echo $return | sed -n 's/.*\({"error"[: ]\+\({[^}]*}\)*}\).*/\1/p'
  exit 1
fi
