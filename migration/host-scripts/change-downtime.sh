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

# Description: This script changes the seconds of downtime configuration of
# an SEV-encrypted VM prior to or during migration.

print_help() {
  echo "Tool to change maximal downtime during the migration of an SEV-encrypted VM."
  echo " "
  echo "Run with: ./change-downtime.sh <seconds> -s </path/to/dir>"
  echo " "
  echo "options:"
  echo "-h, --help                                Show this help"
  echo "-s, --source-directory </path/to/dir>     Directory in which to operate on source (locally)"
}

# -----------------------------------------------------------------
if [[ $# == 0 || $# -ne 3 ]]; then
  print_help
  exit 0
fi

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  -s | --source-directory)
    shift
    SOURCE_PATH="${1%/}"
    shift
    ;;
  *)
    seconds="$1"
    re='^[0-9.]+$'
    if ! [[ "$seconds" =~ $re ]]; then
      echo "ERROR: seconds must be a number."
      exit 1
    fi
    shift
    ;;
  esac
done

QMP_SOCK=$(realpath "$SOURCE_PATH/qmp_sock")
#set params
if test ! -S "$QMP_SOCK"; then
  echo "ERROR: Could not find qmp socket in specified source path."
  exit 1
fi
data=$( (
  echo
  sleep .01
  echo '{ "execute": "qmp_capabilities" }'
  sleep .01
  echo '{ "execute": "migrate_set_downtime", "arguments": { "value": '$seconds' } }'
  sleep .01
) | nc -U "$QMP_SOCK" -N)
if [[ $(echo "$data" | grep error | wc -l) != 0 ]]; then
  echo "ERROR: failed to set migration downtime?"
  exit 1
fi
echo "[STATUS] Updated maximal downtime."
