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

# Description: This script obtains the measure of an initialized
# SEV-encrypted VM on this machine.

set -e

if [[ "$#" != 1 ]]; then
  echo "Run with ./get_measure.sh <path>"
  echo "Obtains measurement as soon as available and writes it into launch_measure.bin"
  exit 1
fi

BASE_PATH="${1%/}"
if [ ! -d "$BASE_PATH" ]; then
  echo "ERROR: path does not exist?"
  exit 1
fi
QMP_SOCK="qmp_sock"

count=0
while true; do
  if [ ! -S "$BASE_PATH/$QMP_SOCK" ]; then
    if [[ "$count" == 30 ]]; then
      echo "ERROR: no socket found?"
      exit 1
    fi
  else
    test=$( (
      echo
      sleep .01
      echo '{ "execute": "qmp_capabilities" }'
      sleep .1
    ) | nc -U "$BASE_PATH/$QMP_SOCK" -N | grep "return" | wc -l)
    if [[ "$test" > 0 ]]; then
      break
    fi
    if [[ "$count" == 30 ]]; then
      echo "ERROR: socket brocken?"
      exit 1
    fi
  fi
  let count=count+1
  sleep .1
done

data=$( (
  echo
  sleep .01
  echo '{ "execute": "qmp_capabilities" }'
  sleep .01
  echo '{"execute": "query-sev-launch-measure"}'
  sleep .01
) | nc -U "$BASE_PATH/$QMP_SOCK" -N | grep "data")
launch_measure=$(echo "$data" | sed -e "s,.*{\"data\".*\"\(.*\)\".*,\1,")
echo "$launch_measure" | base64 -d >"$BASE_PATH/launch_measure.bin"
